.PHONY: all clean repl test

all:
	jbuilder build --dev

repl:
	jbuilder utop src -- -require pds-reachability

test:
	jbuilder runtest --dev

clean:
	jbuilder clean
