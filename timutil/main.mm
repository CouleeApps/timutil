// Copyright (c) 2019, Glenn Smith
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the <organization> nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#include <string>
#include <vector>
#include <unistd.h>
#include <getopt.h>

//Let RAII do the GC that I don't want to do
template<typename T, auto ffn>
struct AutoFree {
	T thing;
	AutoFree(T thing) : thing(thing) {}
	~AutoFree() {
		ffn(thing);
	}
	operator const T() const { return thing; }
	operator T() { return thing; }
};

//CF types are all so similar
template<typename T>
using CFReleased = AutoFree<T, CFRelease>;

//Converting CF types to cpp types
std::string cstr(const CFStringRef &cfstr) {
	CFIndex bufferSize = CFStringGetLength(cfstr);
	//Need to allocate space
	std::string cstr = std::string(bufferSize, '\00');
	//Tell CF we have 1 extra char so it doesn't go "oh shit they don't have enough space" and give us nothing
	CFStringGetCString(cfstr, (char *)cstr.data(), bufferSize + 1, kCFStringEncodingUTF8);
	return cstr;
}

template<typename T>
std::vector<T> carr(const CFArrayRef &cfarr) {
	std::vector<T> cvec;

	CFIndex count = CFArrayGetCount(cfarr);
	cvec.reserve(count);
	for (CFIndex i = 0; i < count; i ++) {
		cvec.push_back((T)CFArrayGetValueAtIndex(cfarr, i));
	}

	return cvec;
}

void PrintCurrentInputSourceName() {
	CFReleased<TISInputSourceRef> cfInputSource = TISCopyCurrentKeyboardInputSource();
	CFStringRef cfName = (CFStringRef)TISGetInputSourceProperty(cfInputSource, kTISPropertyLocalizedName);

	std::string name = cstr(cfName);
	printf("%s\n", name.c_str());
}

void ListInputSources(bool all) {
	CFReleased<CFMutableDictionaryRef> cfProperties = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, NULL, NULL);
	CFDictionaryAddValue(cfProperties, kTISPropertyInputSourceCategory, kTISCategoryKeyboardInputSource);

	CFReleased<CFArrayRef> cfSources = TISCreateInputSourceList(cfProperties, all);
	std::vector<TISInputSourceRef> sources = carr<TISInputSourceRef>(cfSources);

	std::sort(sources.begin(), sources.end(), [](TISInputSourceRef a, TISInputSourceRef b) {
		CFStringRef cfNameA = (CFStringRef)TISGetInputSourceProperty(a, kTISPropertyLocalizedName);
		CFStringRef cfNameB = (CFStringRef)TISGetInputSourceProperty(b, kTISPropertyLocalizedName);

		return CFStringCompare(cfNameA, cfNameB, kCFCompareCaseInsensitive) == kCFCompareLessThan;
	});

	for (TISInputSourceRef cfInputSource : sources) {
		CFStringRef cfName = (CFStringRef)TISGetInputSourceProperty(cfInputSource, kTISPropertyLocalizedName);

		std::string name = cstr(cfName);
		printf("%s\n", name.c_str());
	}
}

bool SetCurrentInputSource(const std::string &newSourceName) {
	CFReleased<CFMutableDictionaryRef> cfProperties = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, NULL, NULL);
	CFDictionaryAddValue(cfProperties, kTISPropertyInputSourceCategory, kTISCategoryKeyboardInputSource);

	CFReleased<CFArrayRef> cfSources = TISCreateInputSourceList(cfProperties, false);
	std::vector<TISInputSourceRef> sources = carr<TISInputSourceRef>(cfSources);
	for (TISInputSourceRef cfInputSource : sources) {
		CFStringRef cfName = (CFStringRef)TISGetInputSourceProperty(cfInputSource, kTISPropertyLocalizedName);
		std::string name = cstr(cfName);

		if (name == newSourceName) {
			OSStatus err = TISSelectInputSource(cfInputSource);
			return err != noErr;
		}
	}

	return false;
}

void PrintUsage(const char *argv0) {
	printf("Usage: %s --list\n", argv0);
	printf("Usage: %s --current\n", argv0);
	printf("Usage: %s --set <name>\n", argv0);
}

int main(int argc, char * const *argv) {
	bool list_all = false;

	while (1) {
		static option long_options[] = {
			{"help",    no_argument,       0, 'h'},
			{"all",     no_argument,       0, 'a'},
			{"list",    no_argument,       0, 'l'},
			{"current", no_argument,       0, 'c'},
			{"set",     required_argument, 0, 's'},
			{0, 0, 0, 0}
		};

		int option_index = 0;
		int c = getopt_long(argc, argv, "alcs:", long_options, &option_index);

		//End
		if (c == -1)
			break;

		switch (c) {
			case 'a':
				list_all = true;
				break;
			case 'l':
				ListInputSources(list_all);
				return EXIT_SUCCESS;
			case 'c':
				PrintCurrentInputSourceName();
				return EXIT_SUCCESS;
			case 's':
				if (SetCurrentInputSource(optarg)) {
					return EXIT_SUCCESS;
				} else {
					return EXIT_FAILURE;
				}
			case '?':
			case 'h':
				PrintUsage(argv[0]);
				break;
			default:
				PrintUsage(argv[0]);
				break;
		}
	}
	PrintUsage(argv[0]);
	return EXIT_FAILURE;
}
