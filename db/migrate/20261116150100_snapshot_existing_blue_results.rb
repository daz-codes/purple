# Older attempts can only retain the content still available at upgrade time. Do not rewrite their
# recorded score or XP: earlier content revisions cannot be recovered from the action log.
class SnapshotExistingBlueResults < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  def up
    safety_assured do
      execute <<~SQL
        UPDATE shift_attempts AS attempts
        SET result_content = to_jsonb(shifts) || jsonb_build_object(
          'track', (SELECT to_jsonb(tracks) FROM tracks WHERE tracks.id = shifts.track_id),
          'hints', COALESCE((SELECT jsonb_agg(to_jsonb(hints) ORDER BY hints.position)
            FROM hints WHERE hints.shift_id = shifts.id), '[]'::jsonb),
          'messages', COALESCE((SELECT jsonb_agg(to_jsonb(messages) || jsonb_build_object(
            'links', COALESCE((SELECT jsonb_agg(to_jsonb(links) ORDER BY links.id)
              FROM links WHERE links.message_id = messages.id), '[]'::jsonb),
            'red_flags', COALESCE((SELECT jsonb_agg(to_jsonb(red_flags) ORDER BY red_flags.id)
              FROM red_flags WHERE red_flags.message_id = messages.id), '[]'::jsonb),
            'techniques', COALESCE((SELECT jsonb_agg(to_jsonb(techniques) ORDER BY techniques.id)
              FROM techniques JOIN message_techniques ON message_techniques.technique_id = techniques.id
              WHERE message_techniques.message_id = messages.id), '[]'::jsonb)
          ) ORDER BY messages.position) FROM messages WHERE messages.shift_id = shifts.id), '[]'::jsonb)
        )
        FROM shifts
        WHERE attempts.shift_id = shifts.id AND attempts.status <> 'open' AND attempts.result_content = '{}'
      SQL
    end
  end

  def down
    # Captured content belongs to the attempt and is retained until the column is removed.
  end
end
