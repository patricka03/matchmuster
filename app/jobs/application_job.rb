class ApplicationJob < ActiveJob::Base
  # ========================================
  # RETRIES
  # ========================================

  # Database deadlocks are usually temporary.
  # Retry instead of permanently failing the job.
  retry_on ActiveRecord::Deadlocked,
           wait: :polynomially_longer,
           attempts: 5

  # ========================================
  # DISCARDS
  # ========================================

  # If a job contains a serialized model that has
  # since been deleted, there is nothing useful
  # left for the job to process.
  discard_on ActiveJob::DeserializationError
end
