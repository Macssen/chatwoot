# == Schema Information
#
# Table name: calls
#
#  id                   :bigint           not null, primary key
#  direction            :integer          not null
#  duration_seconds     :integer
#  end_reason           :string
#  meta                 :jsonb
#  provider             :integer          default("twilio"), not null
#  provider_call_id     :string           not null
#  started_at           :datetime
#  status               :string           default("ringing"), not null
#  transcript           :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  accepted_by_agent_id :bigint
#  account_id           :bigint           not null
#  contact_id           :bigint           not null
#  conversation_id      :bigint           not null
#  inbox_id             :bigint           not null
#  message_id           :bigint
#
# Indexes
#
#  index_calls_on_account_id_and_contact_id       (account_id,contact_id)
#  index_calls_on_account_id_and_conversation_id  (account_id,conversation_id)
#  index_calls_on_message_id                      (message_id)
#  index_calls_on_provider_and_provider_call_id   (provider,provider_call_id) UNIQUE
#
class Call < ApplicationRecord
  include Rails.application.routes.url_helpers

  DEFAULT_STUN_URLS = ['stun:stun.l.google.com:19302'].freeze

  STATUS_RINGING = 'ringing'.freeze
  STATUS_IN_PROGRESS = 'in-progress'.freeze
  TERMINAL_STATUSES = %w[completed busy failed rejected no-answer canceled missed].freeze
  STATUSES = ([STATUS_RINGING, STATUS_IN_PROGRESS] + TERMINAL_STATUSES).freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :contact
  belongs_to :message, optional: true
  belongs_to :accepted_by_agent, class_name: 'User', optional: true

  has_one_attached :recording

  enum provider: { twilio: 0, whatsapp: 1 }
  enum direction: { incoming: 0, outgoing: 1 }

  validates :provider_call_id, presence: true, uniqueness: { scope: :provider }
  validates :status, inclusion: { in: STATUSES }

  # meta holds provider-specific session state: SDP for WhatsApp WebRTC,
  # conference identifiers for Twilio bridging.
  store_accessor :meta, :sdp_offer, :sdp_answer, :ice_servers, :conference_sid, :recording_sid

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }

  after_update_commit :dispatch_message_update

  def self.default_ice_servers
    urls = ENV.fetch('VOICE_CALL_STUN_URLS', nil).presence&.split(',')&.map(&:strip) || DEFAULT_STUN_URLS
    [{ urls: urls }]
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # Applies a status transition. Terminal states are sticky so late or
  # out-of-order provider webhooks can't resurrect an ended call.
  def apply_status!(new_status, end_reason: nil)
    return if terminal?
    return if new_status == status

    self.status = new_status
    self.end_reason = end_reason if end_reason.present?
    self.started_at ||= Time.current if new_status == STATUS_IN_PROGRESS
    compute_duration if TERMINAL_STATUSES.include?(new_status)
    save!
  end

  def recording_url
    return unless recording.attached?

    url_for(recording)
  end

  # Serialized into message payloads (cable + REST). Keys are snake_case;
  # the dashboard camelizes on ingestion.
  def push_event_data
    {
      id: id,
      provider: provider,
      provider_call_id: provider_call_id,
      status: status,
      direction: direction,
      accepted_by_agent_id: accepted_by_agent_id,
      accepted_by_agent_name: accepted_by_agent&.available_name,
      recording_url: recording_url,
      transcript: transcript,
      duration_seconds: duration_seconds,
      end_reason: end_reason,
      inbox_id: inbox_id,
      conversation_id: conversation.display_id
    }
  end

  private

  def compute_duration
    return if started_at.blank?

    self.duration_seconds ||= (Time.current - started_at).round
  end

  # Status changes must repaint the voice_call bubble and the conversation
  # card, both of which render from the message's call payload.
  def dispatch_message_update
    return if message.blank?
    return unless saved_change_to_status? || saved_change_to_duration_seconds?

    Rails.configuration.dispatcher.dispatch(Events::Types::MESSAGE_UPDATED, Time.zone.now, message: message.reload)
  end
end
