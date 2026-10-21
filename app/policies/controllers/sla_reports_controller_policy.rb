# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Controllers::SlaReportsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!(['ticket.agent', 'admin', 'report'])

  def ticket_sla?
    true
  end
end

