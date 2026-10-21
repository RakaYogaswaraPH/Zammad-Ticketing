# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class ActivityStreamPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      res = if customer?
              scope.where(id: nil)
            elsif group_ids.blank?
              scope.where(permission_id: permission_ids, group_id: nil)
            else
              scope.where(permission_id: [*permission_ids, nil], group_id: [*group_ids, nil])
                .where.not('permission_id IS NULL AND group_id IS NULL')
            end

      # Non-admin users (e.g. pure agents) should not see sensitive session started activity events
      if !admin?
        session_started_id = TypeLookup.by_name('session started')
        res = res.where.not(activity_stream_type_id: session_started_id) if session_started_id
      end

      res
    end

    private

    def admin?
      user.roles.exists?(name: 'Admin')
    end

    def customer?
      !user.permissions?(%w[admin ticket.agent])
    end

    def permission_ids
      @permission_ids ||= user.permissions_with_child_ids
    end

    def group_ids
      @group_ids ||= user.group_ids_access('read')
    end
  end
end
