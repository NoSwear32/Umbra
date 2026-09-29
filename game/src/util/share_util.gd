class_name ShareUtil
extends RefCounted
## Sharing text (replays) with the outside world.
##
## The text is ALWAYS copied to the clipboard first (works everywhere, needs no permission).
## On Android the system share sheet is additionally opened through the engine's
## JavaClassWrapper (a plain ACTION_SEND text intent - no file access, no permissions).


## Returns true if the Android share sheet was launched; the clipboard copy always happens.
static func share_text(subject: String, text: String) -> bool:
	DisplayServer.clipboard_set(text)
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return false
	var runtime: Variant = Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		return false
	var activity: Variant = runtime.getActivity()
	if activity == null:
		return false
	var intent_class: Variant = JavaClassWrapper.wrap("android.content.Intent")
	if intent_class == null:
		return false
	var intent: Variant = intent_class.Intent()
	if intent == null:
		return false
	intent.setAction("android.intent.action.SEND")
	intent.setType("text/plain")
	intent.putExtra("android.intent.extra.SUBJECT", subject)
	intent.putExtra("android.intent.extra.TEXT", text)
	var chooser: Variant = intent_class.createChooser(intent, subject)
	if chooser == null:
		return false
	activity.startActivity(chooser)
	return true
