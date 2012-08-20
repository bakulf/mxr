BIN_PATH = /usr/bin

MXR_BIN_FILE = mxr.rb
MXR_BIN_NAME = mxr
TRY_BIN_FILE = try.rb
TRY_BIN_NAME = try

install:
	@cp $(MXR_BIN_FILE) $(BIN_PATH)/$(MXR_BIN_FILE)
	@cp $(TRY_BIN_FILE) $(BIN_PATH)/$(TRY_BIN_FILE)
	@rm -f $(BIN_PATH)/$(MXR_BIN_NAME)
	@ln -s $(BIN_PATH)/$(MXR_BIN_FILE) $(BIN_PATH)/$(MXR_BIN_NAME)
	@rm -f $(BIN_PATH)/$(TRY_BIN_NAME)
	@ln -s $(BIN_PATH)/$(TRY_BIN_FILE) $(BIN_PATH)/$(TRY_BIN_NAME)
