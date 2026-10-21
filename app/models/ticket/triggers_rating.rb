# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Ticket::TriggersRating
  extend ActiveSupport::Concern

  included do
    after_commit :trigger_rating_on_close, on: %i[create update]
  end

  private

  def trigger_rating_on_close
    return if Setting.get('import_mode')
    return unless ticket_is_closed?
    return unless previous_changes['state_id'].present? || previous_changes['close_at'].present?

    TelegramRatingHandler.trigger_if_closed(self)
  rescue => e
    Rails.logger.error "[Ticket::TriggersRating] error: #{e.message}"
  end

  def ticket_is_closed?
    return false if state_id.blank?

    state = Ticket::State.lookup(id: state_id)
    return false if state.blank?

    state_type = Ticket::StateType.lookup(id: state.state_type_id)
    state_type&.name == 'closed'
  end
end

