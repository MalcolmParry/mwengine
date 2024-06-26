#include "pch.h"

#include "Logger.h"

namespace mwengine {
	std::unique_ptr<Logger::Profile> app;
	std::unique_ptr<Logger::Profile> core;

	Logger::Profile GetAppLogger() {
		if (app.get() == nullptr) {
			Logger::Profile* profilePtr = new Logger::Profile("App", Logger::Color::MakeColor(Logger::Color::None, Logger::Color::Black));

			app.reset(profilePtr);
		}

		return *app.get();
	}

	Logger::Profile GetCoreLogger() {
		if (core.get() == nullptr) {
			Logger::Profile* profilePtr = new Logger::Profile("Core", Logger::Color::MakeColor(Logger::Color::None, Logger::Color::Gray));

			core.reset(profilePtr);
		}

		return *core.get();
	}
}