require 'test_helper'

class Application::ExtendObjectsControllerTest < ActionController::TestCase
  def setup
    super
    login_as_application_subject :lauren
    @choice = FactoryGirl.create(:choice)
    @object = FactoryGirl.create(:object, :aasm_state => 'approved', :choices => [@choice])
    @expected_params = {
        :object_id                 => @object.id,
        :dynamic_exp => "true",
        :dynamic_time        => 4,
        :immovable_exp        => nil
      }
    @request.env['HTTP_REFERER'] = application_extend_objects_path
  end

  context "authorized users" do
    should "not allow unauthorized access" do
      post :create
      assert_response 403
    end

    should "only allow authorized access" do
      external_people(:lauren).subject.roles << roles(:object_extend_mgr)
      post :create
      assert :success
    end
  end

  context "params" do
    should "handle blank parameters" do
      assert_nothing_raised do
        post :create, :object_id => @object.id
        post :create, :object_id => @object.id, :dynamic_exp => ''
      end
    end

    should "call service object with correct parameters" do
      external_people(:lauren).subject.roles << roles(:object_extend_mgr)
      post :create, @expected_params
      assert :success
      assert_equal '4 months', @object.reload.choices.first.process_time
    end

    context "messages" do
      should "return error messages from failed service due to no object_id" do
        Timecop.freeze(Time.zone.parse("2015-11-02 12:00:00 ET"))
        external_people(:lauren).subject.roles << roles(:object_extend_mgr)
        Services::Result.any_instance.stubs(:success?).returns(false)
        Services::Result.any_instance.stubs(:errors).returns("No available object with ID: ")
        post :create, :immovable_exp => 2.months.from_now
        assert_equal ["Must provide object_id"], flash[:error]
        Timecop.return
      end

      should "return success messages_for_flash when update succeeds" do
        Timecop.freeze(Time.zone.parse("2015-11-02 12:00:00 ET"))
        external_people(:lauren).subject.roles << roles(:object_extend_mgr)
        post :create, :object_id => @object.id, :dynamic_exp => "false", :immovable_exp => 7.months.from_now
        assert :success
        expected_messages = "Updated Object #{@object.id} with expiration date: 2016-06-02.; \nchoices have been updated."
        assert_equal expected_messages, flash[:notice]
        Timecop.return
      end
    end
  end
end
