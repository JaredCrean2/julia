NAME = julia
SRCS = jltypes gf ast repl builtins module codegen interpreter alloc dlload \
	io init task
OBJS = $(SRCS:%=%.o)
DOBJS = $(SRCS:%=%.do)
EXENAME = $(NAME)
LLTDIR = lib
FLISPDIR = flisp
LLT = $(LLTDIR)/libllt.a
FLISP = $(FLISPDIR)/libflisp.a

JULIAHOME = .

NBITS = $(shell (test -e nbits || $(CC) nbits.c -o nbits) && ./nbits)
include ./Make.inc.$(shell uname)

FLAGS = -falign-functions -Wall -Wno-strict-aliasing \
	-I$(FLISPDIR) -I$(LLTDIR) $(HFILEDIRS:%=-I%) $(LIBDIRS:%=-L%) \
	$(CFLAGS) $(CONFIG) -I$(shell llvm-config --includedir) \
	-fvisibility=hidden
LIBFILES = $(FLISP) $(LLT)
LIBS = $(LIBFILES) -lutil -ldl -lm -lgc -lreadline $(OSLIBS) \
	$(shell llvm-config --ldflags --libs engine)

DEBUGFLAGS = -ggdb3 -DDEBUG $(FLAGS) -DENABLE_INFERENCE
SHIPFLAGS = -O3 -DNDEBUG $(FLAGS) -DENABLE_INFERENCE

default: debug

%.o: %.c julia.h
	$(CC) $(SHIPFLAGS) -c $< -o $@
%.do: %.c julia.h
	$(CC) $(DEBUGFLAGS) -c $< -o $@
%.o: %.cpp julia.h
	$(CXX) $(SHIPFLAGS) $(shell llvm-config --cppflags) -c $< -o $@
%.do: %.cpp julia.h
	$(CXX) $(DEBUGFLAGS) $(shell llvm-config --cppflags) -c $< -o $@

ast.o ast.do: julia_flisp.boot.inc
julia_flisp.boot.inc: julia_flisp.boot $(FLISP)
	$(FLISPDIR)/flisp ./bin2hex.scm < $< > $@
julia_flisp.boot: julia-parser.scm julia-syntax.scm \
	match.scm utils.scm jlfrontend.scm $(FLISP)
	$(FLISPDIR)/flisp ./jlfrontend.scm
codegen.o codegen.do: intrinsics.cpp

julia-defs.s.bc: julia-defs$(NBITS).s
	llvm-as -f $< -o $@

julia-defs.s.bc.inc: julia-defs.s.bc bin2hex.scm $(FLISP)
	$(FLISPDIR)/flisp ./bin2hex.scm < $< > $@

$(LLT): $(LLTDIR)/*.h $(LLTDIR)/*.c
	cd $(LLTDIR) && $(MAKE)

$(FLISP): $(FLISPDIR)/*.h $(FLISPDIR)/*.c $(LLT)
	cd $(FLISPDIR) && $(MAKE)

julia-debug: $(DOBJS) $(LIBFILES)
	$(CXX) $(DEBUGFLAGS) $(DOBJS) -o $@ $(LIBS)

julia-release: $(OBJS) $(LIBFILES)
	$(CXX) $(SHIPFLAGS) $(OBJS) -o $@ $(LIBS)

debug release: %: julia-%
	ln -sf julia-$@ julia

test: debug
	./julia tests.j

clean:
	rm -f *.o
	rm -f *.do
	rm -f *.bc
	rm -f *.bc.inc
	rm -f julia_flisp.boot
	rm -f julia_flisp.boot.inc
	rm -f $(EXENAME)
	rm -f *~ *#

cleanall: clean
	rm -f nbits
	rm -rf $(EXENAME)-{debug,release}
	$(MAKE) -C $(LLTDIR) clean
	$(MAKE) -C $(FLISPDIR) clean

.PHONY: debug release test clean cleanall
