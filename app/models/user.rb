# == Schema Information
#
# Table name: users
#
#  id                   :integer          not null, primary key
#  username             :string           not null
#  email                :string           not null
#  encrypted_password   :string           default(""), not null
#  remember_created_at  :datetime
#  sign_in_count        :integer          default(0), not null
#  current_sign_in_at   :datetime
#  last_sign_in_at      :datetime
#  current_sign_in_ip   :string
#  last_sign_in_ip      :string
#  confirmation_token   :string
#  confirmed_at         :datetime
#  confirmation_sent_at :datetime
#  created_at           :datetime
#  updated_at           :datetime
#  unconfirmed_email    :string
#  role                 :integer          not null
#  checkins_count       :integer          default(0), not null
#  notifications_count  :integer          default(0), not null
#  share_checkin        :boolean          default(FALSE)
#
# Indexes
#
#  index_users_on_confirmation_token  (confirmation_token) UNIQUE
#  index_users_on_email               (email) UNIQUE
#  index_users_on_role                (role)
#  index_users_on_username            (username) UNIQUE
#

class User < ActiveRecord::Base
  # registrations#createが実行されたあとメールアドレスの確認を挟まず
  # ログインできるようにするため、Confirmableモジュールを直接includeする
  include Devise::Models::Confirmable

  include UserCheckable
  include UserFollowable
  include UserLikable
  include UserReceivable

  extend Enumerize

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :recoverable, :rememberable
  devise :database_authenticatable, :omniauthable, :registerable,
         :trackable, omniauth_providers: [:facebook, :twitter]

  enumerize :role, in: { user: 0, admin: 1, editor: 2 }, default: :user

  has_many :activities,    dependent: :destroy
  has_many :channel_works, dependent: :destroy
  has_many :checkins,      dependent: :destroy
  has_many :checks,        dependent: :destroy
  has_many :finished_tips, dependent: :destroy
  has_many :follows,       dependent: :destroy
  has_many :followings,    through:   :follows
  has_many :r_likes,       dependent: :destroy, class_name: 'Like'
  has_many :notifications, dependent: :destroy
  has_many :providers,     dependent: :destroy
  has_many :receptions,    dependent: :destroy
  has_many :channels,      through:   :receptions
  has_many :statuses,      dependent: :destroy
  has_one  :profile,       dependent: :destroy
  has_one  :setting,       dependent: :destroy

  validates :email, presence: true, uniqueness: true, email: true
  validates :username, presence: true, uniqueness: true, length: { maximum: 20 },
                       format: { with: /\A[A-Za-z0-9_]+\z/ }

  after_commit :publish_events, on: :create


  def checking_works
    @checking_works ||= CheckingWorks.new(read_attribute(:checking_works))
  end

  def works
    @works ||= UserWorksQuery.new(self)
  end

  def episodes
    @episodes ||= UserEpisodesQuery.new(self)
  end

  def programs
    @programs ||= UserProgramsQuery.new(self)
  end

  def tips
    @tips ||= UserTipsQuery.new(self)
  end

  def social_friends
    @social_friends ||= UserSocialFriendsQuery.new(self)
  end

  def build_relations(oauth)
    self.providers.build do |p|
      p.name             = oauth[:provider]
      p.uid              = oauth[:uid]
      p.token            = oauth[:credentials][:token]
      p.token_expires_at = oauth[:credentials][:expires_at]
      p.token_secret     = oauth[:credentials][:secret]
    end

    self.build_profile do |p|
      p.name         = oauth[:info][:name].presence || oauth[:info][:nickname]
      p.description  = oauth[:info][:description]
      p.tombo_avatar = URI.parse(get_large_avatar_image(oauth[:provider], oauth[:info][:image]))
    end

    self.build_setting

    self
  end

  def following_activities
    following_ids = followings.pluck(:id)
    following_ids << self.id

    Activity.where(user_id: following_ids)
  end

  def watching_count
    statuses.where(latest: true).with_kind(:watching).count
  end

  def authorized_to?(provider)
    providers.pluck(:name).include?(provider.to_s)
  end

  def provider_name
    providers.first.name.humanize
  end

  def read_notifications!
    transaction do
      unread_count = notifications.unread.update_all(read: true)
      decrement!(:notifications_count, unread_count)
    end
  end

  def shareable_to?(provider_name)
    providers.pluck(:name).include?(provider_name.to_s)
  end

  def hide_checkin_comment?(checkin)
    checkin.comment.present? &&
    checkin.user != self &&
    setting.hide_checkin_comment? &&
    works.desiring_to_watch.include?(checkin.episode.work) &&
    !checkins.pluck(:episode_id).include?(checkin.episode_id)
  end

  private

  def get_large_avatar_image(provider, image_url)
    url = case provider
          when 'twitter'  then image_url.sub('_normal', '')
          when 'facebook' then "#{image_url.sub("http://", "https://")}?type=large"
          end
    url
  end

  def publish_events
    UsersEvent.publish(:create, self)
  end
end
