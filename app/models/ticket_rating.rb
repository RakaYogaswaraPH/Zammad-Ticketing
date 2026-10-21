# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketRating < ApplicationModel
  belongs_to :ticket
  belongs_to :customer, class_name: 'User'
  belongs_to :agent, class_name: 'User'

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :ticket_id, uniqueness: { scope: :agent_id }

  after_commit :update_agent_stats, on: %i[create update destroy]

  def self.participating_agents(ticket)
    # Find all users who posted an article in this ticket, excluding customer
    agent_ids = Ticket::Article.where(ticket_id: ticket.id)
                               .where.not(created_by_id: ticket.customer_id)
                               .reorder(nil)
                               .distinct
                               .pluck(:created_by_id)
    User.where(id: agent_ids)
  end

  def update_agent_stats
    return if agent_id.blank?

    stats = TicketRating.where(agent_id: agent_id).pick(
      Arel.sql('COALESCE(ROUND(AVG(rating)::numeric, 2), 0.0)'),
      Arel.sql('COUNT(*)')
    )

    avg = stats ? stats[0].to_f : 0.0
    total = stats ? stats[1].to_i : 0

    User.where(id: agent_id).update_all(average_rating: avg, total_ratings: total)
  end
end

