# F12a: the organizations (a firm, a group): they gather entities and name the people who manage the gathering. Joining one gives access to nothing: a
# person still sees an entity only through their membership of that entity. Only an owner of the organization changes it, and only an owner of an entity
# puts it in or takes it out.
class OrganizationsController < ApplicationController
  skip_before_action :require_entity!
  before_action :set_organization, only: %i[show update add_entity remove_entity add_member remove_member]
  before_action :require_organization_owner, only: %i[update add_entity remove_entity add_member remove_member]

  def index
    @organizations = mine.order(:name)
  end

  def new
    @organization = Organization.new
  end

  def create
    @organization = Organization.new(name: params.dig(:organization, :name), created_by: current_user)
    saved = Organization.transaction do
      @organization.save && @organization.organization_memberships.create!(user: current_user, role: "owner")
    end
    saved ? redirect_to(organization_path(@organization), notice: "Organization created.") : render(:new, status: :unprocessable_content)
  end

  def show
    @members = @organization.organization_memberships.includes(:user).order(:id)
    @entities = @organization.entities.order(:name).select { |entity| Portfolio::Access.membership(current_user, entity) }
    @hidden_count = @organization.entities.count - @entities.size
    @addable = current_user.current_entities.merge(UserEntity.owners).where(organization_id: nil).order(:name)
    @owner = @organization.owner?(current_user)
  end

  def update
    @organization.update(name: params.dig(:organization, :name)) ? redirect_to(organization_path(@organization), notice: "Saved.") : redirect_to(organization_path(@organization), alert: @organization.errors.full_messages.to_sentence)
  end

  def add_entity
    entity = current_user.current_entities.merge(UserEntity.owners).find_by(id: params[:entity_id])
    return redirect_to(organization_path(@organization), alert: "Only the owner of a dossier puts it in an organization.") unless entity

    entity.update!(organization: @organization)
    redirect_to organization_path(@organization), notice: "#{entity.name} added."
  end

  def remove_entity
    entity = @organization.entities.find(params[:entity_id])
    return redirect_to(organization_path(@organization), alert: "Only the owner of a dossier takes it out.") unless Portfolio::Access.owner?(current_user, entity)

    entity.update!(organization: nil)
    redirect_to organization_path(@organization), notice: "#{entity.name} taken out."
  end

  def add_member
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    return redirect_to(organization_path(@organization), alert: "No one has that e-mail address.") unless user

    membership = @organization.organization_memberships.build(user: user, role: OrganizationMembership::ROLES.include?(params[:role]) ? params[:role] : "member")
    membership.save ? redirect_to(organization_path(@organization), notice: "Added.") : redirect_to(organization_path(@organization), alert: membership.errors.full_messages.to_sentence)
  end

  def remove_member
    membership = @organization.organization_memberships.find(params[:membership_id])
    membership.destroy ? redirect_to(organization_path(@organization), notice: "Removed.") : redirect_to(organization_path(@organization), alert: membership.errors.full_messages.to_sentence)
  end

  private

  def mine = Organization.joins(:organization_memberships).where(organization_memberships: { user_id: current_user.id })

  def set_organization = @organization = mine.find(params[:id])

  def require_organization_owner
    redirect_to organization_path(@organization), alert: "Only an owner of the organization does that." unless @organization.owner?(current_user)
  end
end
