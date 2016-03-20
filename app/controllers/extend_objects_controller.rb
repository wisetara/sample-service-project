class Application::ExtendObjectsController < Application::BaseController
  include StandardAggregateLayout

  def index
    respond_to do |format|
      format.html
    end
  end

  def create
    parse_object_id
    parse_dynamic_time
    parse_dynamic_exp

    service_params = {
      :object_id     => @object_id,
      :dynamic_exp   => @dynamic_expiration,
      :immovable_exp => @exp_date,
      :dynamic_time  => @dynamic_time
    }

    result = Services::ExtendObjectImmovableDynamic.perform(service_params)
    if result.success?
      flash[:notice] = result.data[:notice]
    else
      flash[:error] = result.data[:errors]
    end
    render :index
  end

  def parse_object_id
    if params[:object_id].nil? || params[:object_id].empty?
      @object_id = nil
    else
      d_id = params[:object_id]
      @object_id = d_id.to_i
    end
  end

  def parse_dynamic_time
    if params[:dynamic_time].nil? || params[:dynamic_time].empty?
      @dynamic_time = nil
    else
      parse_interval = params.try(:[], :dynamic_time)
      @dynamic_time = parse_interval.to_i
    end
  end

  def parse_dynamic_exp
    if params[:dynamic_exp] == "true"
      @dynamic_expiration = true
      @exp_date = nil
    else
      @dynamic_expiration = false
      @dynamic_time = nil
      @exp_date = params.try(:[], :immovable_exp)
    end
  end
end
