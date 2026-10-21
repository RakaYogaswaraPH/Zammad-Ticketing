# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Stats::TicketEscalation

  def self.generate(user)
    # Agent performance rating
    avg_rating = user.average_rating.to_f
    total_ratings = user.total_ratings.to_i

    # Fallback to TicketRating directly if needed
    if total_ratings.zero? && defined?(TicketRating)
      ratings = TicketRating.where(agent_id: user.id)
      total_ratings = ratings.count
      avg_rating = total_ratings.positive? ? ratings.average(:rating).to_f.round(2) : 0.0
    end

    state = if total_ratings.zero?
              'good'
            elsif avg_rating >= 4.5
              'supergood'
            elsif avg_rating >= 3.5
              'good'
            elsif avg_rating >= 2.5
              'ok'
            elsif avg_rating >= 1.5
              'bad'
            else
              'superbad'
            end

    own_text = if total_ratings.positive?
                 "#{avg_rating.round(1)} ⭐"
               else
                 'Belum Ada'
               end

    {
      used_for_average:  avg_rating,
      average_per_agent: avg_rating,
      state:             state,
      average_rating:    avg_rating,
      total_ratings:     total_ratings,
      own:               own_text,
      total:             total_ratings,
    }
  end

  def self.average_state(result, _user_id)
    result
  end

end
