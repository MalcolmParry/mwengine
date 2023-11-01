#pragma once

#include "Core.h"
#include "Keycode.h"
#include <functional>

#include <string>

namespace mwengine {
	namespace EventTypes {
		enum EventTypes {
			WindowClosed, WindowMoved, WindowResize, WindowFocus, WindowLostFocus,
			KeyDown, KeyUp, KeyChar,
			MouseMoved, MouseDown, MouseUp
		};
	}

	typedef EventTypes::EventTypes EventType;

	namespace EventCategories {
		enum EventCategories {
			Window = MW_BIT(0),
			Input = MW_BIT(1),
			Keyboard = MW_BIT(2),
			Mouse = MW_BIT(3)
		};
	}

	typedef EventCategories::EventCategories EventCategory;

	class Event {
	public:
		virtual ~Event() {}

		virtual char* GetName() = 0;
		virtual uint8 GetCategoryFlags() = 0;
		virtual bool InCategory(EventCategory category) = 0;
		virtual EventType GetType() = 0;

		virtual inline operator std::string() {
			return GetName();
		}
	};

	typedef std::function<void(Event&)> EventCallback;

	#define EVENT_FUNCTIONS(type, categories)															\
	virtual inline char* GetName() { return #type; }													\
	virtual inline uint8 GetCategoryFlags() { return categories; }										\
	virtual inline bool InCategory(EventCategory category) { return GetCategoryFlags() & category; }	\
	virtual inline EventType GetType() { return EventType::##type; }

	/////////////////////////////////////////////
	/////////////// Window Events ///////////////
	/////////////////////////////////////////////

	class WindowClosedEvent : public Event {
	public:
		WindowClosedEvent() {}
		~WindowClosedEvent() {}

		EVENT_FUNCTIONS(WindowClosed, EventCategory::Window)
	};

	class WindowMovedEvent : public Event {
	public:
		WindowMovedEvent(MWATH::Int2 _position)
			: position(_position) {
		}
		~WindowMovedEvent() {}

		inline MWATH::Int2 GetPosition() { return position; }

		EVENT_FUNCTIONS(WindowMoved, EventCategory::Window)
	private:
		MWATH::Int2 position;
	};

	class WindowResizeEvent : public Event {
	public:
		WindowResizeEvent(MWATH::Int2 _size)
			: size(_size) {
		}
		~WindowResizeEvent() {}

		inline MWATH::Int2 GetSize() { return size; }

		EVENT_FUNCTIONS(WindowResize, EventCategory::Window)
	private:
		MWATH::Int2 size;
	};

	class WindowFocusEvent : public Event {
	public:
		WindowFocusEvent() {}
		~WindowFocusEvent() {}

		EVENT_FUNCTIONS(WindowFocus, EventCategory::Window)
	};

	class WindowLostFocusEvent : public Event {
	public:
		WindowLostFocusEvent() {}
		~WindowLostFocusEvent() {}

		EVENT_FUNCTIONS(WindowLostFocus, EventCategory::Window)
	};

	class KeyDownEvent : public Event {
	public:
		KeyDownEvent(Keycode _keycode, bool _repeat)
			: keycode(_keycode), repeat(_repeat) {
		}
		~KeyDownEvent() {}

		inline Keycode GetKeycode() { return keycode; }
		inline bool IsRepeat() { return repeat; }

		EVENT_FUNCTIONS(KeyDown, EventCategory::Input | EventCategory::Keyboard)
	private:
		Keycode keycode;
		bool repeat;
	};

	class KeyUpEvent : public Event {
	public:
		KeyUpEvent(Keycode _keycode)
			: keycode(_keycode) {
		}
		~KeyUpEvent() {}

		inline Keycode GetKeycode() { return keycode; }

		EVENT_FUNCTIONS(KeyUp, EventCategory::Input | EventCategory::Keyboard)
	private:
		Keycode keycode;
	};

	class KeyCharEvent : public Event {
	public:
		KeyCharEvent(char _c)
			: c(_c) {
		}
		~KeyCharEvent() {}

		inline char GetChar() { return c; }

		EVENT_FUNCTIONS(KeyChar, EventCategory::Input | EventCategory::Keyboard)
	private:
		char c;
	};

	class MouseMovedEvent : public Event {
	public:
		MouseMovedEvent(MWATH::Int2 _position)
			: position(_position) {
		}
		~MouseMovedEvent() {}

		inline MWATH::Int2 GetPosition() { return position; }

		EVENT_FUNCTIONS(MouseMoved, EventCategory::Input | EventCategory::Mouse)
	private:
		MWATH::Int2 position;
	};

	class MouseDownEvent : public Event {
	public:
		MouseDownEvent(MouseCode _mousecode)
			: mousecode(_mousecode) {
		}
		~MouseDownEvent() {}

		inline MouseCode GetMouseCode() { return mousecode; }

		EVENT_FUNCTIONS(MouseDown, EventCategory::Input | EventCategory::Mouse)
	private:
		MouseCode mousecode;
	};

	class MouseUpEvent : public Event {
	public:
		MouseUpEvent(MouseCode _mousecode)
			: mousecode(_mousecode) {
		}
		~MouseUpEvent() {}

		inline MouseCode GetMouseCode() { return mousecode; }

		EVENT_FUNCTIONS(MouseUp, EventCategory::Input | EventCategory::Mouse)
	private:
		MouseCode mousecode;
	};
}

namespace std {
	inline string to_string(mwengine::Event* event) {
		return string(*event);
	}
}