# Built by ../tableau-service.sh for the installed Hyprland, again after an update.
# By hand: make -C hypr/stagethumbs (in the plugin folder)
CXXFLAGS = -shared -fPIC -O2 -std=c++26 -Wall -Wno-deprecated-declarations
INCLUDES = $(shell pkg-config --cflags hyprland pixman-1 libdrm hyprutils hyprlang aquamarine hyprgraphics lua5.5)

stagethumbs.so: main.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) main.cpp -o $@.tmp && mv -f $@.tmp $@

clean:
	rm -f stagethumbs.so

.PHONY: clean
