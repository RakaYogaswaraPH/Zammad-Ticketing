# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Controllers::TicketRatingsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!(['ticket.customer', 'ticket.agent', 'admin'])
end

