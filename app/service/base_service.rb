class BaseService
  # думаю идея понятна )

  def self.call(*args)
    new(*args).call
  end
end
