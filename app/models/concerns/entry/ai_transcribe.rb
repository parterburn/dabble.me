require 'fileutils'

class Entry::AiTranscribe
  OPENAI_WHISPER_MODEL = "whisper-1".freeze
  OPENAI_MODEL = "gpt-3.5-turbo".freeze
  OPENAI_TEMPERATURE = 0.3 # 0-1.0, higher = more creative

  # Entry::AiTranscribe.new.batch_ai_transcribe("/Users/user/Downloads/files", "mp3")
  def batch_ai_transcribe(folder_path, filetype="mp3")
    all_audio_files = audio_files(folder_path, filetype)
    all_audio_files.each do |file_path|
      @transcription = nil
      @formatted_transcription = nil
      @transcription = ai_transcribe(file_path)
      @formatted_transcription = respond_as_ai_editor

      if @error.present?
        if @error&.dig("error", "code") == "context_length_exceeded"
          create_and_move_transcription_file(file_path, "@transcription")
          puts "Transcribed with Whisper: #{file_path}"
        else
          puts "*ERROR WITH*: #{file_path}"
          puts "*#{OPENAI_MODEL.upcase}*: #{@error}"
        end
      else
        create_and_move_transcription_file(file_path, "@formatted_transcription")
        puts "Transcribed with Whisper and GPT: #{file_path}"
      end
    end
  end

  private

  def audio_files(folder_path, filetype)
    # Use Dir.glob to get an array of all wav files in the folder
    mp3_files = Dir.glob("#{folder_path}/*.#{filetype}")

    # Loop through the array of mp3 files and get their names
    mp3_files.map do |file_path|
      "#{folder_path}/#{File.basename(file_path)}"
    end
  end

  def create_and_move_transcription_file(file_path, transcription_type)
    txt_file_path = "#{file_path}.txt"

    # Write the transcription to a file in same folder
    File.open(txt_file_path, "w") do |file|
      file.write(instance_variable_get(transcription_type))
    end

    # Use FileUtils.mv to move the file
    FileUtils.mv(file_path, file_path.split("/").insert(-2, "transcribed").join("/"))
    FileUtils.mv(txt_file_path, txt_file_path.split("/").insert(-2, "transcribed").join("/"))
  end

  def client
    OpenAI::Client.new(request_timeout: 240)
  end

  def max_tokens
    if OPENAI_MODEL == "gpt-4"
      8000
    else
      4000
    end
  end

  def ai_transcribe(file_path)
    resp = client.transcribe(
      parameters: {
          model: OPENAI_WHISPER_MODEL,
          file: File.open(file_path, "rb"),
      })
    resp["text"]
  end

  def respond_as_ai_editor
    @error = nil
    resp = client.chat(
      parameters: {
        model: OPENAI_MODEL,
        messages: as_transcription_editor,
        temperature: OPENAI_TEMPERATURE,
        max_tokens: max_tokens
      }
    )
    if resp["choices"].present?
      resp.dig("choices", 0, "message", "content")
    else
      @error = resp
    end
  end

  def as_transcription_editor
    [
      {
        role: "system",
        content: %(You are an expert speech-to-text editor. The user's text is from a voice dictation system of a phone conversation between two people. You are to add paragraphs (attempting to split between the two people talking), punctuation, remove ums and other filler words, and clarify the wording. Fix any words that the auto dictation software likely misheard.)
      },
      {
        role: "user",
        content: @transcription
      }
    ]
  end
end
