class EntitiesController < ApplicationController
  skip_before_action :require_entity!, only: %i[index new create]

  def index
    @entities = current_user.entities.active.order(:name)
  end

  def new
    @entity = Entity.new
  end

  def create
    @entity = Entity.new(entity_params.merge(created_by: current_user))

    if @entity.save
      result = Entities::ProvisionEntity.call(entity: @entity, created_by: current_user)
      if result.success?
        session[:current_entity_id] = @entity.id
        redirect_to accounting_root_path, notice: t("entities.provisioned")
      else
        @entity.destroy
        flash.now[:alert] = t("entities.provision_failed")
        render :new, status: :unprocessable_content
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  def switch
    entity = current_user.entities.find_by(id: params[:id])
    if entity
      session[:current_entity_id] = entity.id
      redirect_to accounting_root_path, notice: t("entities.switched", name: entity.name)
    else
      redirect_to entities_path, alert: t("entities.not_found")
    end
  end

  private

  def entity_params
    params.require(:entity).permit(:name, :legal_name, :vat_number, :country, :legal_form,
                                   :address_line1, :address_line2, :city, :zip_code)
  end
end
