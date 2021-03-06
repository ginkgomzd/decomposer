
# # #
# Validation and Derived Configurations
# # #

ifndef STACK
STACK := $(if $(wildcard .active),\
	$(subst STACK=,,$(shell grep STACK $(wildcard .active))))
INACTIVE := $(if $(wildcard .active),\
	$(subst INACTIVE=,,$(shell grep INACTIVE $(wildcard .active))))
endif

STACK := $(strip ${STACK})

ifndef STACK
STACK := NULL# enable few commands to run, such as help and command completion
endif

ifneq (${STACK},NULL)
STACK_NAME := $(shell echo "${STACK}" | tr A-Z a-z)
STACK_ID := $(shell echo "${STACK}" | tr a-z A-Z)
include ${STACK_NAME}.stack
endif

# do not change default goal by this include:
.DEFAULT_GOAL_CACHED := ${.DEFAULT_GOAL}

# # #
# Helpers
# # #

if-file-in = $(if $(wildcard $1/$2), $1/$2)

rm-file = $(if $(shell (test -L $1 || test -e $1) && echo 'TRUE'), \
	$(shell rm -f $1 && echo 'rm -f $1'))

# # #
# Generate derived docker-compose files
# # #

# # #
# /dev/null to avoid error from `cat` if no env files are used.
# include service or task env files in docker/
# include *.stack.env in project directory
# include additional files from stack configuration (ENV_INCLUDES)
# TODO: confirm/document precedence
define stack-env-includes
/dev/null \
$(foreach svc,${STACK_SERVICES} ${TASK},$(call if-file-in,docker,${svc}.env)) \
$(foreach stk,${STACK_SERVICES} ${STACK_ID} ${TASK},$(call if-file-in,.,${stk}.stack.env)) \
${ENV_INCLUDES}
endef

%.stack.env: ${stack-env-includes}
	$(info using $(filter-out /dev/null,$^))
	@cat $^ >$@

.INTERMEDIATE: ${STACK_NAME}.stack.env # enable auto-clean-up of generated files

.env: ${STACK_NAME}.stack.env
	@cp $< $@

# # #
# include YAML files named for the STACK in supported locations
# include service/task definitions in docker/
define stack-config-includes
$(foreach type,network volume config conf,$(call if-file-in,${type},${STACK_NAME}.yml))\
$(foreach svc,${STACK_SERVICES},$(call if-file-in,docker,${svc}.yml))
endef

%-compose.yml: ${stack-config-includes}
	$(info using $^)
	@docker-compose --project-directory=. $(foreach f,$^,-f $f) config > $@ 2>/dev/null

.INTERMEDIATE: ${STACK_NAME}-compose.yml # enable auto-clean-up of generated files

docker-compose.yml: ${STACK_NAME}-compose.yml
	@cp $< $@

ifdef DEBUG
$(info STACK::${STACK})
$(info stack-config-includes::$(strip ${stack-config-includes}))
$(info stack-env-includes::$(strip ${stack-env-includes}))
endif

# # #
# Commands
# # #

activate:
ifeq (${STACK},NULL)
	$(eval export STACK=${INACTIVE})
endif
	@$(MAKE) --quiet .env docker-compose.yml 
	@echo "STACK=${STACK}" > .active
	$(info STACK:${STACK})
	$(info SERVICES:${STACK_SERVICES})

deactivate:
	$(foreach f,.env docker-compose.yml ${STACK_NAME}.stack.env ${STACK_NAME}-compose.yml,\
		$(call rm-file,$f))
ifneq (${STACK},NULL)
	echo "INACTIVE=${STACK}" > .active
endif

# # #
# set and customize docker-compose commands
# and implement custom actions
# # #

custom-actions := down rund orphans services

# # #
# docker compose sub-commands
#
define set-action
$(filter-out ${custom-actions},$*)\
$(if $(filter down,$*),$(if ${TASK},rm --force --stop,down))\
$(if $(filter orphans,$*),down --remove-orphans)\
$(if $(filter rund,$*),run -d)\
$(if $(filter run,$*),--rm)\
$(if $(filter up,$*),-d)\
$(if $(filter services,$*),config --services)
endef

# # #
# docker run command-parameter
#
define set-run-cmd
$(if $(filter rund run exec,$*),\
$(if ${RUN_CMD},\
$(if $(filter 1,$(words ${RUN_CMD})),${RUN_CMD},'${RUN_CMD}')\
)) ${CMD_ARGS}
endef

# # #
# docker-compose wrapper
# # #

#
# we set project-dir explicitly because we do not want it determined by include file dirs.
#
dkc-%: $(if $(filter-out NULL,${STACK}),docker-compose.yml) $(if $(filter-out NULL,${STACK}),.env) 
	@docker-compose --project-dir=. $(if $(wildcard docker/${TASK}.yml), -f docker/${TASK}.yml) \
	$(set-action) ${DK_CMP_OPTS} \
	$(if ${WORKING_DIR},$(if $(filter rund run exec,$*),--workdir ${WORKING_DIR})) \
	$(if $(filter-out config,$*),${TASK}) $(set-run-cmd)
ifdef DEBUG
	$(info ACTION::$(set-action) ${DK_CMP_OPTS} RUN-CMD::$(set-run-cmd))
endif

# # #
# Aliases
# # #

ENABLE_ALIASES := $(if $(and $(wildcard docker-compose.yml),$(wildcard .env)),ENABLE)

#
# Aliases that do not require a STACK definition
#

run: dkc-run
rund: dkc-rund

#
# Aliases that do require a STACK definition
#
ifdef ENABLE_ALIASES
build: dkc-build
config: dkc-config
create: dkc-create
down: dkc-down
events: dkc-events
exec: dkc-exec
logs: dkc-logs
orphans: dkc-orphans # alias, `down --remove-orphans`
pause: dkc-pause
restart: dkc-restart
rm: dkc-rm
services: dkc-services
start: dkc-start
stop: dkc-stop
top: dkc-top
unpause: dkc-unpause
up: dkc-up
endif

# restore default goal.
.DEFAULT_GOAL := ${.DEFAULT_GOAL_CACHED}