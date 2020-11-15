class EntryApproveForm < Entry
  include ActiveFormModel

  validates :resume, presence: true
end