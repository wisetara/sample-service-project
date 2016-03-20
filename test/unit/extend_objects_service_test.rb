require 'test_helper'

class Services::ExtendObjectImmovableDynamicTest < ActiveSupport::TestCase

  setup do
    @object_dynamic_to_immovable = FactoryGirl.create(:object, :exp_date => 6.months.from_now)
    @object_immovable_to_dynamic = FactoryGirl.create(:object, :exp_date => 3.months.from_now)

    # dynamic to immovable
    @service_to_immovable = Services::ExtendObjectImmovableDynamic.new(:object_id => @object_dynamic_to_immovable.id,
                                                                       :dynamic_exp => false,
                                                                       :immovable_exp => 5.months.from_now,
                                                                       :dynamic_time => nil)
    # immovable to dynamic
    @service_to_dynamic = Services::ExtendObjectImmovableDynamic.new(:object_id => @object_immovable_to_dynamic.id,
                                                                     :dynamic_exp => true,
                                                                     :immovable_exp => nil,
                                                                     :dynamic_time => 5)

    @contractd_by = FactoryGirl.create(:subject, :email => "test@example.com")
  end

  context "Getting an object" do
    should "return valid params with a valid object_id" do
      immovable_result = @service_to_immovable.perform
      dynamic_result = @service_to_dynamic.perform
      immovable_data = immovable_result.data
      dynamic_data = dynamic_result.data

      assert_equal @object_dynamic_to_immovable.id, immovable_data[:object_id]
      assert_equal @object_immovable_to_dynamic.id, dynamic_data[:object_id]

      assert_equal :success, immovable_result.status
      assert_equal :success, dynamic_result.status
    end

    should "fix up an oddly-submitted immovable_exp date" do
      Timecop.freeze(Time.parse("2015-11-02 12:00:00 ET"))
      expected_exp_date = '10/07/2016'
      odd_date_service = Services::ExtendObjectImmovableDynamic.new(:object_id => @object_dynamic_to_immovable.id,
                                                                    :dynamic_exp => false,
                                                                    :immovable_exp => expected_exp_date,
                                                                    :dynamic_time => nil)

      odd_date_result = odd_date_service.perform
      odd_date_data = odd_date_result.data
      assert_equal Date.parse(expected_exp_date), @object_dynamic_to_immovable.reload.exp_date
      assert_equal :success, odd_date_result.status
      Timecop.return
    end

    should "fix up or error out a dynamic_time that is not an integer" do
      expected_dynamic_time = '5 monkeys'
      weird_dynamic_service = Services::ExtendObjectImmovableDynamic.new(:object_id => @object_immovable_to_dynamic.id,
                                                                         :dynamic_exp => true,
                                                                         :immovable_exp => nil,
                                                                         :dynamic_time => expected_dynamic_time)
      weird_dynamic_result = weird_dynamic_service.perform
      weird_dynamic_data = weird_dynamic_result.data
      assert_equal "#{expected_dynamic_time.to_i} months", @object_immovable_to_dynamic.reload.choices.first.process_time
      assert_equal :success, weird_dynamic_result.status
    end

    should "fail if an object is not found" do
      nil_id_service = Services::ExtendObjectImmovableDynamic.new(:object_id => nil,
                                                                  :dynamic_exp => false,
                                                                  :immovable_exp => 4.months.from_now,
                                                                  :dynamic_time => nil)
      nil_result = nil_id_service.perform
      assert_equal :invalid_input, nil_result.status

      bad_id_service = Services::ExtendObjectImmovableDynamic.new(:object_id => 99999999,
                                                                  :dynamic_exp => false,
                                                                  :immovable_exp => 4.months.from_now,
                                                                  :dynamic_time => nil)
      bad_id_result = bad_id_service.perform
      assert_equal :failure, bad_id_result.status
    end

    should "fail if a dynamic_time isn't provided for a dynamic_expiration" do
      missing_interval_service = Services::ExtendObjectImmovableDynamic.new(:object_id => @object_immovable_to_dynamic.id,
                                                                            :dynamic_exp => true,
                                                                            :immovable_exp => nil)
      assert_raise(Services::PerformService::MissingInputData) do
        missing_interval_service.perform
      end
      assert_nothing_raised(Services::PerformService::MissingInputData) do
        @service_to_dynamic.perform
      end
    end

    should "fail if a immovable_exp isn't provided for a immovable expiration" do
      missing_immovable_service = Services::ExtendObjectImmovableDynamic.new(:object_id => @object_dynamic_to_immovable.id,
                                                                             :dynamic_exp => false,
                                                                             :dynamic_time => nil)
      assert_raise(Services::PerformService::MissingInputData) do
        missing_immovable_service.perform
      end
      assert_nothing_raised(Services::PerformService::MissingInputData) do
        @service_to_immovable.perform
      end
    end
  end

  context "For objects that end up dynamic" do
    setup do
      contract = FactoryGirl.create(:contract_draw, :object => @object_immovable_to_dynamic, :subject => @contractd_by)
      documents = contract.documents
      documents.each do |document|
        document.activate!
      end
      @original_runs_out = @object_immovable_to_dynamic.documents.first.runs_out
      @contract_date = @object_immovable_to_dynamic.documents.first.contract.try(:created_at)
    end

    should "update the documents with dynamic_time" do
      Timecop.freeze(Time.parse("2015-11-02 12:00:00 ET"))
      @service_to_dynamic.perform
      @object_immovable_to_dynamic.reload

      assert_equal true, @object_immovable_to_dynamic.dynamic_expiration?
      assert_equal nil, @object_immovable_to_dynamic.exp_date

      assert_not_equal @original_runs_out, @object_immovable_to_dynamic.documents.first.runs_out
      assert_equal (@contract_date + 5.months).to_date, @object_immovable_to_dynamic.documents.first.runs_out.to_date
      assert_no_difference("documents.count") do
        @service_to_dynamic.perform
      end
      Timecop.return
    end

    should "update the object choices" do
      @service_to_dynamic.perform
      @object_immovable_to_dynamic.reload

      @object_immovable_to_dynamic.choices.each do |o|
        assert_equal "5 months", o.process_time
        assert_not_nil o.immovable_completion_date
        assert_equal true, o.dynamic_expiration
      end
    end

    should "reflect a nil exp_date for dynamic object" do
      @service_to_dynamic.perform
      @object_immovable_to_dynamic.reload

      assert_nil @object_immovable_to_dynamic.exp_date
    end

    should "set the correct key and messages" do
      @service_to_dynamic.perform
      @object_immovable_to_dynamic.reload
      expected_messages_for_flash = "Updated Object #{@object_immovable_to_dynamic.id} with dynamic_expiration for 5 months.; \nImmovable_completion_date updated to: #{@object_immovable_to_dynamic.choices.first.immovable_completion_date}."

      assert @service_to_dynamic.messages_for_flash
      assert_equal expected_messages_for_flash, @service_to_dynamic.messages_for_flash
    end
  end

  context "For objects that end up immovable" do
    setup do
      contract = FactoryGirl.create(:contract_draw, :object => @object_dynamic_to_immovable, :subject => @contractd_by)
      documents = contract.documents
      documents.each do |document|
        document.activate!
      end
      @original_runs_out = @object_dynamic_to_immovable.documents.first.runs_out
    end

    should "update the documents with the provided expiration date" do
      @service_to_immovable.perform
      @object_dynamic_to_immovable.reload
      expected_exp_date = 5.months.from_now.in_time_zone(@object_dynamic_to_immovable.timezone).beginning_of_day

      assert_not_equal @original_runs_out, @object_dynamic_to_immovable.documents.first.runs_out
      assert_equal expected_exp_date.to_date, @object_dynamic_to_immovable.documents.first.runs_out.to_date
      assert_no_difference("documents.count") do
        @service_to_immovable.perform
      end
    end

    should "update the object choices" do
      @service_to_immovable.perform
      @object_dynamic_to_immovable.reload

      @object_dynamic_to_immovable.choices.each do |o|
        assert_nil o.process_time
        assert_nil o.immovable_completion_date
        assert_equal false, o.dynamic_expiration
      end
    end

    should "update the object with the provided expiration date for immovable objects" do
      @service_to_immovable.perform
      @object_dynamic_to_immovable.reload
      expected_exp_date = 5.months.from_now.in_time_zone(@object_dynamic_to_immovable.timezone).beginning_of_day

      assert_equal false, @object_dynamic_to_immovable.dynamic_expiration?
      assert_equal expected_exp_date.to_date, @object_dynamic_to_immovable.exp_date.to_date
    end

    should "set the correct key and messages" do
      Timecop.freeze(Time.zone.parse("2015-11-02 12:00:00 ET"))
      object_dynamic_to_immovable = FactoryGirl.create(:object, :exp_date => 6.months.from_now)
      service_to_immovable = Services::ExtendObjectImmovableDynamic.new(:object_id => object_dynamic_to_immovable.id,
                                                                        :dynamic_exp => false,
                                                                        :immovable_exp => 5.months.from_now,
                                                                        :dynamic_time => nil)
      service_to_immovable.perform
      assert service_to_immovable.messages_for_flash.include?("Updated Object #{object_dynamic_to_immovable.id} with expiration date: 2016-04-02")
      Timecop.return
    end

    should "display the correct messages when there is a validation error" do
      Timecop.freeze(Time.zone.parse("2015-11-02 12:00:00 ET"))
      object_dynamic_to_immovable = FactoryGirl.create(:object, :exp_date => 6.months.from_now)
      service_to_immovable = Services::ExtendObjectImmovableDynamic.new(:object_id => object_dynamic_to_immovable.id,
                                                                        :dynamic_exp => false,
                                                                        :immovable_exp => 5.days.ago,
                                                                        :dynamic_time => nil)
      result = service_to_immovable.perform
      data = result.data
      expected_error_message = "Object DID NOT SAVE WITH NEW INFORMATION DUE TO ERROR: Expires on must be in the future and greater than or equal to offer end"

      assert_equal :failure, result.status
      refute data[:errors].blank?
      assert data[:errors].include?(expected_error_message)
      Timecop.return
    end
  end
end