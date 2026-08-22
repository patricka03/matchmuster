class PushDevicesController < ApplicationController
  before_action :authenticate_user!

  def create
    token = push_device_params[:token]
    platform = push_device_params[:platform]

    push_device =
      PushDevice.find_or_initialize_by(
        token: token
      )

    push_device.user = current_user
    push_device.platform = platform

    if push_device.save
      render json: {
        message: "Push device registered successfully.",
        push_device: {
          id: push_device.id,
          platform: push_device.platform
        }
      }, status: :ok
    else
      render json: {
        errors: push_device.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    token = push_device_params[:token]

    push_device =
      current_user.push_devices.find_by(
        token: token
      )

    unless push_device
      render json: {
        error: "Push device not found."
      }, status: :not_found

      return
    end

    push_device.destroy!

    render json: {
      message: "Push device removed successfully."
    }, status: :ok
  end

  private

  def push_device_params
    params.require(:push_device).permit(
      :token,
      :platform
    )
  end
end
