# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'telegram/bot'
require 'cgi'

class TelegramRatingHandler
  def self.trigger_if_closed(ticket)
    return unless ticket_closed?(ticket)

    chat_id = ticket.preferences&.dig(:telegram, :chat_id) || ticket.preferences&.dig('telegram', 'chat_id')
    return if chat_id.blank?

    channel_id = ticket.preferences&.dig(:channel_id) || ticket.preferences&.dig('channel_id')
    channel = Channel.find_by(id: channel_id) if channel_id.present?
    channel ||= Channel.find_by(area: 'Telegram::Bot', active: true)
    return if channel.blank? || channel.options[:api_token].blank?

    agents = TicketRating.participating_agents(ticket)
    return if agents.blank?

    rated_agent_ids = TicketRating.where(ticket_id: ticket.id).pluck(:agent_id)
    pending_agents = agents.reject { |a| rated_agent_ids.include?(a.id) }
    return if pending_agents.blank?

    send_agent_prompt(channel, chat_id, ticket, pending_agents.first)
  rescue => e
    Rails.logger.error "[TelegramRatingHandler] trigger error: #{e.message}"
  end

  def self.handle_callback(callback_query, channel)
    cq = callback_query.respond_to?(:to_unsafe_h) ? callback_query.to_unsafe_h : callback_query
    data = (cq[:data] || cq['data']).to_s
    cq_id = cq[:id] || cq['id']
    chat_id = cq.dig(:message, :chat, :id) || cq.dig('message', 'chat', 'id')
    token = channel.options[:api_token]

    # Handle Skip Comment
    if data.start_with?('rate_skip:')
      parts = data.split(':')
      return unless parts.length == 3

      ticket_id = parts[1].to_i
      agent_id = parts[2].to_i
      ticket = Ticket.lookup(id: ticket_id)
      return if ticket.blank?

      # Clear waiting comment state
      Rails.cache.delete("tg_rating_waiting:#{chat_id}")

      Telegram::Bot::Client.run(token) do |bot|
        bot.api.answerCallbackQuery(
          callback_query_id: cq_id,
          text: 'Komentar dilewati.'
        )

        # Check remaining unrated agents
        all_agents = TicketRating.participating_agents(ticket)
        rated_ids = TicketRating.where(ticket_id: ticket.id).pluck(:agent_id)
        remaining = all_agents.reject { |a| rated_ids.include?(a.id) }

        if remaining.any?
          send_agent_prompt(channel, chat_id, ticket, remaining.first)
        else
          bot.api.sendMessage(
            chat_id: chat_id,
            text: "🎉 <b>Terima kasih banyak!</b>\n\nSemua petugas yang membantu kendala Anda pada Tiket <b>##{ticket.number}</b> telah dinilai.\nPenilaian Anda sangat berarti bagi peningkatan kualitas layanan kami. 🙏",
            parse_mode: 'HTML'
          )
        end
      end
      return
    end

    # Handle Star Rating
    parts = data.split(':')
    return unless parts[0] == 'rate' && parts.length == 4

    ticket_id = parts[1].to_i
    agent_id = parts[2].to_i
    rating_val = parts[3].to_i

    ticket = Ticket.lookup(id: ticket_id)
    agent = User.lookup(id: agent_id)

    return if ticket.blank? || agent.blank? || !ticket_closed?(ticket)

    # Simpan atau update nilai rating bintang
    rating_record = TicketRating.find_or_initialize_by(ticket_id: ticket.id, agent_id: agent.id)
    rating_record.customer_id = ticket.customer_id
    rating_record.rating = rating_val
    rating_record.save!

    # Simpan state menunggu komentar dari user ini di Telegram
    Rails.cache.write("tg_rating_waiting:#{chat_id}", {
      ticket_id: ticket.id,
      agent_id: agent.id,
      rating: rating_val
    }, expires_in: 30.minutes)

    Telegram::Bot::Client.run(token) do |bot|
      bot.api.answerCallbackQuery(
        callback_query_id: cq_id,
        text: "⭐ Penilaian #{rating_val} bintang berhasil dicatat!"
      )

      skip_button = Telegram::Bot::Types::InlineKeyboardButton.new(
        text: '⏩ Lewati / Tanpa Komentar',
        callback_data: "rate_skip:#{ticket.id}:#{agent.id}"
      )
      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [[skip_button]]
      )

      star_str = '⭐' * rating_val
      agent_display = CGI.escapeHTML(agent.fullname.presence || agent.firstname || 'Petugas')

      prompt_text = "⭐ <b>Penilaian #{star_str} (#{rating_val}/5) untuk #{agent_display} berhasil dicatat!</b>\n\n" \
                    "💬 <b>Tuliskan komentar atau kesan pelayanan Anda:</b>\n" \
                    "<i>(Ketik dan kirim balasan pesan teks langsung di chat ini)</i>\n\n" \
                    "Atau tekan tombol di bawah jika tidak ingin meninggalkan komentar."

      bot.api.sendMessage(
        chat_id: chat_id,
        text: prompt_text,
        parse_mode: 'HTML',
        reply_markup: keyboard
      )
    end
  rescue => e
    Rails.logger.error "[TelegramRatingHandler] callback error: #{e.message}"
  end

  def self.handle_message(message, channel)
    msg = message.respond_to?(:to_unsafe_h) ? message.to_unsafe_h : message
    chat_id = msg.dig(:chat, :id) || msg.dig('chat', 'id')
    text = (msg[:text] || msg['text']).to_s.strip
    return false if chat_id.blank? || text.blank?

    state = Rails.cache.read("tg_rating_waiting:#{chat_id}")
    return false if state.blank?

    ticket_id = state[:ticket_id] || state['ticket_id']
    agent_id = state[:agent_id] || state['agent_id']

    ticket = Ticket.lookup(id: ticket_id)
    agent = User.lookup(id: agent_id)
    return false if ticket.blank? || agent.blank?

    # Simpan komentar ke record rating
    rating_record = TicketRating.find_or_initialize_by(ticket_id: ticket.id, agent_id: agent.id)
    rating_record.customer_id = ticket.customer_id
    rating_record.comment = text
    rating_record.save!

    # Hapus state menunggu komentar
    Rails.cache.delete("tg_rating_waiting:#{chat_id}")

    token = channel.options[:api_token]
    Telegram::Bot::Client.run(token) do |bot|
      agent_display = CGI.escapeHTML(agent.fullname.presence || agent.firstname || 'Petugas')
      comment_display = CGI.escapeHTML(text)

      bot.api.sendMessage(
        chat_id: chat_id,
        text: "✅ <b>Terima kasih!</b> Komentar Anda untuk <b>#{agent_display}</b> berhasil disimpan:\n\n<i>\"#{comment_display}\"</i>",
        parse_mode: 'HTML'
      )

      # Check remaining unrated agents
      all_agents = TicketRating.participating_agents(ticket)
      rated_ids = TicketRating.where(ticket_id: ticket.id).pluck(:agent_id)
      remaining = all_agents.reject { |a| rated_ids.include?(a.id) }

      if remaining.any?
        send_agent_prompt(channel, chat_id, ticket, remaining.first)
      else
        bot.api.sendMessage(
          chat_id: chat_id,
          text: "🎉 <b>Semua penilaian untuk Tiket ##{ticket.number} telah selesai!</b>\n\nKritik dan saran Anda sangat berarti bagi peningkatan kualitas layanan kami. 🙏",
          parse_mode: 'HTML'
        )
      end
    end

    true
  rescue => e
    Rails.logger.error "[TelegramRatingHandler] handle_message error: #{e.message}"
    false
  end

  def self.send_agent_prompt(channel, chat_id, ticket, agent)
    token = channel.options[:api_token]

    buttons = (1..5).map do |stars|
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{'⭐' * stars} (#{stars})",
        callback_data: "rate:#{ticket.id}:#{agent.id}:#{stars}"
      )
    end

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
      inline_keyboard: [
        [buttons[0], buttons[1], buttons[2]],
        [buttons[3], buttons[4]]
      ]
    )

    agent_display = CGI.escapeHTML(agent.fullname.presence || agent.firstname || 'Petugas')
    text = "📋 <b>Penilaian Layanan IT Helpdesk</b>\n\n" \
           "Tiket <b>##{ticket.number}</b> telah selesai ditutup.\n" \
           "Mohon berikan penilaian untuk pelayanan:\n\n" \
           "👤 <b>Petugas/Agent:</b> #{agent_display}\n\n" \
           "Pilih rating bintang Anda di bawah ini:"

    Telegram::Bot::Client.run(token) do |bot|
      bot.api.sendMessage(
        chat_id: chat_id,
        text: text,
        parse_mode: 'HTML',
        reply_markup: keyboard
      )
    end
  end

  def self.ticket_closed?(ticket)
    return false if ticket.blank? || ticket.state_id.blank?

    state = Ticket::State.lookup(id: ticket.state_id)
    return false if state.blank?

    state_type = Ticket::StateType.lookup(id: state.state_type_id)
    state_type&.name == 'closed'
  end
end
