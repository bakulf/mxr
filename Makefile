BIN_PATH = /usr/bin

BIN_FILE = mxr.rb
BIN_NAME = mxr

install:
	@cp $(BIN_FILE) $(BIN_PATH)/$(BIN_FILE)
	@ln -s $(BIN_PATH)/$(BIN_FILE) $(BIN_PATH)/$(BIN_NAME)
