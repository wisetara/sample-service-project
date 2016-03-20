module Services
  class ExtendObjectImmovableDynamic < Services::PerformService
    include CommonServiceValidations

    input_data :object_id,
               :dynamic_exp,
               :immovable_exp,
               :dynamic_time

    perform_steps :validate_input,
                  :get_object,
                  :update_the_object_and_choices,
                  :update_messages,
                  :update_documents,
                  :finish

    def validate_input
      validate_param_exists("object_id", object_id)
      validate_param_exists("dynamic expiration or immovable expiration", dynamic_exp)
      if dynamic_exp
        validate_param_exists("dynamic_time", dynamic_time)
        @dynamic_time = dynamic_time.to_i if dynamic_time.present?
      else
        validate_param_exists("immovable_exp", immovable_exp)
        @immovable_exp = Date.parse(immovable_exp.to_s) if immovable_exp.present?
      end
    end

    def get_object
      @object = Object.find_by_id(object_id)
      finish_with_result :failure, { :errors => "No available object with ID: #{object_id}" } if @object.nil?
    end

    def update_the_object_and_choices
      @object.choices.each do |choice|
        if dynamic_exp
          @process_time = "#{@dynamic_time} months"
          choice.process_time = @process_time
          choice.dynamic_expiration = true
          choice.immovable_completion_date = calculate_immovable_completion_date
          @object.exp_date = nil
          choice.save!
        else
          choice.dynamic_expiration = false
          choice.process_time = nil
          @object.exp_date = @immovable_exp.beginning_of_day
          choice.save!
        end
      end
      if !@object.save
        finish_with_result :failure, { :errors => "Object DID NOT SAVE WITH NEW INFORMATION DUE TO ERROR: #{@object.errors.full_messages.join(", ")}"}
      else
        @object.save!
      end
    end

    def update_messages
      if dynamic_exp
        messages << "Updated Object #{@object.id} with dynamic_expiration for #{@dynamic_time} months."
        messages << "Immovable_completion_date updated to: #{@object.choices.first.immovable_completion_date}."
      else
        messages << "Updated Object #{@object.id} with expiration date: #{@object.exp_date}."
        messages << "choices have been updated."
      end
    end

    def update_documents
      object_documents = document.with_deleted.joins(:contract).where("contracts.object_id = ?", @object.id).readonly(false)
      @documents_count = object_documents.count
      batch_size = 500
      batch_count = @documents_count / batch_size

      object_documents.each_with_index do |document, index|
        contract_date = document.contract.try(:created_at)
        next if contract_date.nil?
        if dynamic_exp
          process_time = @dynamic_time
          @exp_time = (contract_date + process_time.months)
        else
          @exp_time = @immovable_exp
        end
        document.update_attribute(:runs_out, @exp_time.end_of_day)
        messages << "#{index+1} documents for Object #{@object.id} updated to an runs_out date of #{@exp_time}." if batch_count > 0 && ((index+1) % batch_size == 0)
      end
    end

    def finish
      Rails.logger.info("#{Time.now}: Object #{@object_id} was changed via #{self.class} and exp_date #{@object.exp_date} or in #{@process_time}. #{@documents_count} were updated.")
      finish_with_result :success, { :object_id => @object.id, :notice => messages_for_flash }
    end

    def calculate_immovable_completion_date
      if @object.choices.first.immovable_completion_date.nil?
        (@object.opportunity_finishes_at + @dynamic_time.months).to_date
      else
        [(@object.opportunity_finishes_at + @dynamic_time.months).to_date, @object.choices.first.immovable_completion_date].max
      end
    end

    def messages_for_flash
      if has_messages?
        messages.join("; \n")
      end
    end

    def has_messages?
      messages.any?
    end

    def messages
      @messages ||= []
    end
  end
end