# frozen_string_literal: true

module Api
  module V1
    # GET/PATCH /api/v1/app_settings: the iOS app's settings that belong to the account, not the
    # phone, so they come back after signing out or reinstalling and follow the writer to a new
    # phone. Only what was ever set is stored; anything never set is null, so the app can tell
    # "never chosen" (keep this phone's own, and send it up) from "chosen, and empty".
    #
    # - entry_template: the template as typed, a list of runs ({text, bold, italic, underline}),
    #   [] for none
    # - entry_template_auto: whether every new entry starts with it
    # - widget_content: what the medium Home Screen widget shows next to today's date (Settings →
    #   Home Screen Widget). Each widget's own choice (Edit Widget) stays on the phone.
    class AppSettingsController < BaseController
      WIDGET_CONTENTS = %w[prompt promptEntry memoryCount memoryEntry].freeze
      MAX_TEMPLATE_RUNS = 500
      MAX_TEMPLATE_CHARACTERS = 10_000
      RUN_FORMATS = %w[bold italic underline].freeze

      def show
        render json: settings_json(current_user)
      end

      # PATCH { entry_template: [...], entry_template_auto: true, widget_content: "prompt" } (any of them)
      def update
        user = current_user
        # Read, change and save under the row's lock: two phones each sending one setting at once
        # would otherwise each save the whole JSON and lose the other's.
        user.with_lock { apply_update(user) }
      end

      private

      def apply_update(user)
        settings = user.app_settings_hash

        if provided?(:entry_template)
          runs = template_runs(params[:entry_template])
          return render_error(:unprocessable_content, 'invalid', 'That template could not be saved.') if runs.nil?

          settings['entry_template'] = runs
        end
        settings['entry_template_auto'] = boolean(:entry_template_auto) if provided?(:entry_template_auto)
        if provided?(:widget_content)
          content = params[:widget_content].to_s
          return render_error(:unprocessable_content, 'invalid', 'Unknown widget choice.') unless WIDGET_CONTENTS.include?(content)

          settings['widget_content'] = content
        end

        user.app_settings_hash = settings
        if user.save
          render json: settings_json(user)
        else
          render_error(:unprocessable_content, 'invalid', 'Could not save your settings.', details: user.errors.full_messages)
        end
      end

      def settings_json(user)
        settings = user.app_settings_hash
        {
          entry_template: settings['entry_template'],
          entry_template_auto: settings['entry_template_auto'],
          widget_content: settings['widget_content']
        }
      end

      # The runs as the app keeps them, with only the keys it uses; nil when they aren't runs,
      # or there are too many of them.
      def template_runs(value)
        return [] if value.nil?

        list = value.respond_to?(:to_unsafe_h) ? nil : value
        return nil unless list.is_a?(Array) && list.size <= MAX_TEMPLATE_RUNS

        runs = list.map do |run|
          run = run.to_unsafe_h if run.respond_to?(:to_unsafe_h)
          return nil unless run.is_a?(Hash) && run['text'].is_a?(String)

          RUN_FORMATS.each_with_object({ 'text' => run['text'] }) do |format, kept|
            kept[format] = true if ActiveModel::Type::Boolean.new.cast(run[format])
          end
        end
        return nil if runs.sum { |run| run['text'].length } > MAX_TEMPLATE_CHARACTERS

        runs
      end

      # JSON null is "not in this request". The iOS client encodes an unset optional as null,
      # and an emptied template as []. Treating null as a value would clear the template, turn
      # the switch off, or reject the save (a null widget choice is not one of the four).
      def provided?(key)
        params.key?(key) && !params[key].nil?
      end

      def boolean(key)
        ActiveModel::Type::Boolean.new.cast(params[key]) ? true : false
      end
    end
  end
end
