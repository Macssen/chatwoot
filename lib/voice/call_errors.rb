# Typed failures for the voice-call subsystem so controllers can map
# provider errors to meaningful HTTP responses.
module Voice::CallErrors
  # Meta rejects business-initiated calls to contacts that haven't granted
  # call permission with error code 138006.
  META_NO_PERMISSION_CODE = 138_006

  class NoCallPermission < StandardError; end
  class CallFailed < StandardError; end
end
