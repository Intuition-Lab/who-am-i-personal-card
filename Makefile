# 本地开发：Persome Card 后端服务（apps/personal-card/persome-card-server.mjs）的启停封装。
# Electron App 仍走 apps/personal-card 下的 `npm run desktop`。

APP_DIR  := apps/personal-card
RUN_DIR  := .run
PID_FILE := $(RUN_DIR)/card-server.pid
LOG_FILE := $(RUN_DIR)/card-server.log
PORT     ?= 8772

.PHONY: start stop

# 整个 recipe 必须是一条 shell 命令：make 每行 recipe 各起一个 shell，
# 分行写时 "already running" 分支里的 exit 0 拦不住后面的启动行。
start:
	@mkdir -p $(RUN_DIR); \
	if [ -f $(PID_FILE) ] && kill -0 "`cat $(PID_FILE)`" 2>/dev/null; then \
		echo "already running (pid `cat $(PID_FILE)`) -> http://127.0.0.1:$(PORT)/"; \
		exit 0; \
	fi; \
	( cd $(APP_DIR) && WHOAMI_CARD_PORT=$(PORT) exec nohup node persome-card-server.mjs >$(CURDIR)/$(LOG_FILE) 2>&1 ) & \
	echo $$! >$(PID_FILE); \
	i=0; while [ $$i -lt 20 ]; do \
		if curl -sf -o /dev/null http://127.0.0.1:$(PORT)/; then \
			echo "started (pid `cat $(PID_FILE)`) -> http://127.0.0.1:$(PORT)/"; \
			exit 0; \
		fi; \
		i=`expr $$i + 1`; sleep 0.5; \
	done; \
	echo "failed to start, last log lines from $(LOG_FILE):"; \
	tail -20 $(LOG_FILE); \
	rm -f $(PID_FILE); \
	exit 1

stop:
	@if [ -f $(PID_FILE) ] && kill -0 "`cat $(PID_FILE)`" 2>/dev/null; then \
		kill "`cat $(PID_FILE)`"; \
		echo "stopped (pid `cat $(PID_FILE)`)"; \
	else \
		echo "not running"; \
	fi; \
	rm -f $(PID_FILE)
