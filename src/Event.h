#pragma once

#include "Core.h"
#include "Keycode.h"
#include <functional>

#include <string>

namespace mwengine {
	enum EventType {
		EVENT_WINDOW_CLOSED, EVENT_WINDOW_MOVED, EVENT_WINDOW_RESIZE, EVENT_WINDOW_FOCUS, EVENT_WINDOW_LOST_FOCUS,
		EVENT_KEY_DOWN, EVENT_KEY_UP, EVENT_CHAR,
		EVENT_MOUSE_DOWN, EVENT_MOUSE_UP, EVENT_MOUSE_MOVED, EVENT_RAW_MOUSE_MOVED,
		EVENT_LAST = EVENT_RAW_MOUSE_MOVED
	};

	enum EventCategory {
		EVENT_CATEGORY_WINDOW = MW_BIT(0),
		EVENT_CATEGORY_INPUT = MW_BIT(1),
		EVENT_CATEGORY_KEYBOARD = MW_BIT(2),
		EVENT_CATEGORY_MOUSE = MW_BIT(3)
	};

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

	typedef std::function<void(void*, Event&)> EventCallback;

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

		EVENT_FUNCTIONS(EVENT_WINDOW_CLOSED, EVENT_CATEGORY_WINDOW)
	};

	class WindowMovedEvent : public Event {
	public:
		WindowMovedEvent(Math::UInt2 _position)
			: position(_position) {
		}
		~WindowMovedEvent() {}

		inline Math::UInt2 GetPosition() { return position; }

		EVENT_FUNCTIONS(EVENT_WINDOW_MOVED, EVENT_CATEGORY_WINDOW)
	private:
		Math::UInt2 position;
	};

	class WindowResizeEvent : public Event {
	public:
		WindowResizeEvent(Math::UInt2 _size)
			: size(_size) {
		}
		~WindowResizeEvent() {}

		inline Math::UInt2 GetSize() { return size; }

		EVENT_FUNCTIONS(EVENT_WINDOW_RESIZE, EVENT_CATEGORY_WINDOW)
	private:
		Math::UInt2 size;
	};

	class WindowFocusEvent : public Event {
	public:
		WindowFocusEvent() {}
		~WindowFocusEvent() {}

		EVENT_FUNCTIONS(EVENT_WINDOW_FOCUS, EVENT_CATEGORY_WINDOW)
	};

	class WindowLostFocusEvent : public Event {
	public:
		WindowLostFocusEvent() {}
		~WindowLostFocusEvent() {}

		EVENT_FUNCTIONS(EVENT_WINDOW_LOST_FOCUS, EVENT_CATEGORY_WINDOW)
	};

	class KeyDownEvent : public Event {
	public:
		KeyDownEvent(Keycode _keycode, bool _repeat)
			: keycode(_keycode), repeat(_repeat) {
		}
		~KeyDownEvent() {}

		inline Keycode GetKeycode() { return keycode; }
		inline bool IsRepeat() { return repeat; }

		EVENT_FUNCTIONS(EVENT_KEY_DOWN, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_KEYBOARD)
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

		EVENT_FUNCTIONS(EVENT_KEY_UP, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_KEYBOARD)
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

		EVENT_FUNCTIONS(EVENT_CHAR, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_KEYBOARD)
	private:
		char c;
	};

	class MouseDownEvent : public Event {
	public:
		MouseDownEvent(MouseCode _mousecode)
			: mousecode(_mousecode) {
		}
		~MouseDownEvent() {}

		inline MouseCode GetMouseCode() { return mousecode; }

		EVENT_FUNCTIONS(EVENT_MOUSE_DOWN, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_MOUSE)
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

		EVENT_FUNCTIONS(EVENT_MOUSE_UP, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_MOUSE)
	private:
		MouseCode mousecode;
	};

	class MouseMovedEvent : public Event {
	public:
		MouseMovedEvent(Math::Float2 _position)
			: position(_position) {
		}
		~MouseMovedEvent() {}

		inline Math::UInt2 GetPosition() { return position; }

		EVENT_FUNCTIONS(EVENT_MOUSE_MOVED, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_MOUSE)
	private:
		Math::UInt2 position;
	};

	class MouseRawMovedEvent : public Event {
	public:
		MouseRawMovedEvent(Math::Int2 _moved)
			: moved(_moved) {
		}
		~MouseRawMovedEvent() {}

		inline Math::Int2 GetMoved() { return moved; }

		EVENT_FUNCTIONS(EVENT_RAW_MOUSE_MOVED, EVENT_CATEGORY_INPUT | EVENT_CATEGORY_MOUSE)
	private:
		Math::Int2 moved;
	};
}

namespace std {
	inline string to_string(mwengine::Event* event) {
		return string(*event);
	}
}
