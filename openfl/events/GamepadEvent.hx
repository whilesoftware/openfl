package openfl.events;


import openfl.events.Event;

/*
openfl.Lib.application.window.onGamepadAxisMove.add (onGamepadAxisMove);
openfl.Lib.application.window.onGamepadButtonDown.add (onGamepadButtonDown);
openfl.Lib.application.window.onGamepadButtonUp.add (onGamepadButtonUp);
openfl.Lib.application.window.onGamepadConnect.add (onGamepadConnect);
openfl.Lib.application.window.onGamepadDisconnect.add (onGamepadDisconnect);
*/

class GamepadEvent extends Event {
	
	public static inline var AXIS_MOVE:String = "gamepadAxisMove";
	public static inline var BUTTON_DOWN:String = "gamepadButtonDown";
	public static inline var BUTTON_UP:String = "gamepadButtonUp";
	public static inline var GAMEPAD_CONNECT:String = "gamepadConnect";
	public static inline var GAMEPAD_DISCONNECT:String = "gamepadDisconnect";
	
	public var device:Int;
	public var code:Int;
	public var value:Float;
	
	
	public function new (type:String) {
		
		super (type, false, false);
	}
	
	
	public override function clone ():Event {

		var new_gpe:GamepadEvent = new GamepadEvent(type);
		new_gpe.device = device;
		new_gpe.code = code;
		new_gpe.value = value;
		
		return new_gpe;
		
	}
	
	
	public override function toString ():String {
		
		return "[GamepadEvent type=" + type + " bubbles=false cancelable=false device=" + device + " code=" + code + " value=" + value + "]";
		
	}
	
	
}
