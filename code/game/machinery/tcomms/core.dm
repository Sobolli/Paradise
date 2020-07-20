#define UI_TAB_CONFIG "CONFIG"
#define UI_TAB_LINKS "LINKS"
#define UI_TAB_FILTER "FILTER"

/**
  * # Telecommunications Core
  *
  * The core of the entire telecomms operation
  *
  * This thing basically handles the main broadcasting of the data, as well as NTTC configs
  * The relays dont do any actual processing, they are just objects which can bring tcomms to another zlevel
  */
/obj/machinery/tcomms/core
	name = "Telecommunications Core"
	desc = "A large rack full of communications equipment. Looks important."
	icon_state = "core"
	/// The NTTC config for this device
	var/datum/nttc_configuration/nttc = new()
	/// List of all reachable devices
	var/list/reachable_zlevels = list()
	/// List of all linked relays
	var/list/linked_relays = list()
	/// Password for linking stuff together
	var/link_password
	/// What tab of the UI were currently on
	var/ui_tab = UI_TAB_CONFIG

/**
  * Initializer for the core.
  *
  * Calls parent to ensure its added to the GLOB of tcomms machines, before generating a link password and adding itself to the list of reachable Zs.
  */
/obj/machinery/tcomms/core/Initialize(mapload)
	. = ..()
	link_password = GenerateKey()
	reachable_zlevels |= loc.z

/**
  * Destructor for the core.
  *
  * Ensures that the machine is taken out of the global list when destroyed, and also unlinks all connected relays
  */
/obj/machinery/tcomms/core/Destroy()
	for(var/obj/machinery/tcomms/relay/R in linked_relays)
		R.Reset()
	QDEL_NULL(nttc) // Delete the NTTC datum
	linked_relays.Cut() // Just to be sure
	return ..()

/**
  * Helper to see if a zlevel is reachable
  *
  * This is a simple check to see if the input z-level is in the list of reachable ones
  * Returns TRUE if it can, FALSE if it cant
  *
  * Arguments:
  * * zlevel - The input z level to test
  */
/obj/machinery/tcomms/core/proc/zlevel_reachable(zlevel)
	// Nothing is reachable if the core is offline, unpowered, or ion'd
	if(!active || (stat & NOPOWER) || ion)
		return FALSE
	if(zlevel in reachable_zlevels)
		return TRUE
	else
		return FALSE

/**
  * Proc which takes in the message datum
  *
  * Some checks are ran on the signal, and NTTC is applied
  * After that, it is broadcasted out to the required Z-levels
  *
  * Arguments:
  * * tcm - The tcomms message datum
  */
/obj/machinery/tcomms/core/proc/handle_message(datum/tcomms_message/tcm)
	// Don't do anything with rejected signals, if were offline, if we are ion'd, or if we have no power
	if(tcm.reject || !active || (stat & NOPOWER) || ion)
		return FALSE
	// Kill the signal if its on a z-level that isnt reachable
	if(!zlevel_reachable(tcm.source_level))
		return FALSE

	// Now we can run NTTC
	tcm = nttc.modify_message(tcm)

	// If the signal shouldnt be broadcast, dont broadcast it
	if(!tcm.pass)
		// We still return TRUE here because the signal was handled, even though we didnt broadcast
		return TRUE

	// Now we generate the list of where that signal should go to
	tcm.zlevels = reachable_zlevels
	tcm.zlevels |= tcm.source_level

	// Now check if they actually have pieces, if so, broadcast
	if(tcm.message_pieces)
		broadcast_message(tcm)
		return TRUE

	return FALSE

/**
  * Proc to remake the list of available zlevels
  *
  * Loops through the list of connected relays and adds their zlevels in.
  * This is called if a relay is added or removed
  *
  */
/obj/machinery/tcomms/core/proc/refresh_zlevels()
	// Refresh the list
	reachable_zlevels = list()
	// Add itself as a reachable Z-level
	reachable_zlevels |= loc.z
	// Add all the linked relays in
	for(var/obj/machinery/tcomms/relay/R in linked_relays)
		// Only if the relay is active
		if(R.active && !(R.stat & NOPOWER))
			reachable_zlevels |= R.loc.z


//////////////
// UI STUFF //
//////////////

/obj/machinery/tcomms/core/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	// this is silly but it has to be done because NTTC inits before languages do
	if(nttc.valid_languages.len == 1)
		nttc.update_languages()

	// Now the actual UI stuff
	ui = SSnanoui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "tcomms_core.tmpl", "Telecommunications Core", 900, 600)
		ui.open()
		ui.set_auto_update(1)

/obj/machinery/tcomms/core/ui_data(mob/user, ui_key = "main", datum/topic_state/state = GLOB.default_state)
	var/data[0]
	// What tab are we on
	data["tab"] = ui_tab
	data["ion"] = ion

	// Only send NTTC settings if were on the right tab. This saves on sending overhead.
	if(ui_tab == UI_TAB_CONFIG)
		// Z-level list. Note that this will also show sectors with hidden relay links, but you cant see the relays themselves
		// This allows the crew to realise that sectors have hidden relays
		data["sectors_available"] = "Count: [length(reachable_zlevels)] | List: [jointext(reachable_zlevels, " ")]"
		// Toggles
		data["active"] = active
		data["nttc_toggle_jobs"] = nttc.toggle_jobs
		data["nttc_toggle_job_color"] = nttc.toggle_job_color
		data["nttc_toggle_name_color"] = nttc.toggle_name_color
		data["nttc_toggle_command_bold"] = nttc.toggle_command_bold
		// Strings
		data["nttc_setting_language"] = nttc.setting_language
		data["nttc_job_indicator_type"] = nttc.job_indicator_type
		// Network ID
		data["network_id"] = network_id

	if(ui_tab == UI_TAB_LINKS)
		data["link_password"] = link_password
		// You ready to see some shit?
		for(var/obj/machinery/tcomms/relay/R in linked_relays)
			// Dont show relays with a hidden link
			if(R.hidden_link)
				continue
			// Assume false
			var/status = FALSE
			var/status_color = "'background-color: #eb4034'" // Red
			if(R.active && !(R.stat & NOPOWER))
				status = TRUE
				status_color = "'background-color: #32a852'" // Green



			data["entries"] += list(list("addr" = "\ref[R]", "net_id" = R.network_id, "sector" = R.loc.z, "status" = status, "status_color" = status_color))
		// End the shit

	if(ui_tab == UI_TAB_FILTER)
		data["filtered_users"] = nttc.filtering

	return data

/obj/machinery/tcomms/core/Topic(href, href_list)
	// Check against href exploits
	if(..())
		return

	if(href_list["tab"])
		// Make sure its a valid tab
		if(href_list["tab"] in list(UI_TAB_CONFIG, UI_TAB_LINKS, UI_TAB_FILTER))
			ui_tab = href_list["tab"]

	// Check if they did a href, but only for that current tab
	if(ui_tab == UI_TAB_CONFIG)
		// All the toggle on/offs go here
		if(href_list["toggle_active"])
			active = !active
			update_icon()
		// NTTC Toggles
		if(href_list["nttc_toggle_jobs"])
			nttc.toggle_jobs = !nttc.toggle_jobs
			log_action(usr, "toggled job tags (Now [nttc.toggle_jobs])")
		if(href_list["nttc_toggle_job_color"])
			nttc.toggle_job_color = !nttc.toggle_job_color
			log_action(usr, "toggled job colors (Now [nttc.toggle_job_color])")
		if(href_list["nttc_toggle_name_color"])
			nttc.toggle_name_color = !nttc.toggle_name_color
			log_action(usr, "toggled name colors (Now [nttc.toggle_name_color])")
		if(href_list["nttc_toggle_command_bold"])
			nttc.toggle_command_bold = !nttc.toggle_command_bold
			log_action(usr, "toggled command bold (Now [nttc.toggle_command_bold])")
		// We need to be a little more fancy for the others

		// Job Format
		if(href_list["nttc_job_indicator_type"])
			var/card_style = input(usr, "Pick a job card format.", "Job Card Format") as null|anything in nttc.job_card_styles
			if(!card_style)
				return
			nttc.job_indicator_type = card_style
			to_chat(usr, "<span class='notice'>Jobs will now have the style of [card_style].</span>")
			log_action(usr, "has set NTTC job card format to [card_style]")

		// Language Settings
		if(href_list["nttc_setting_language"])
			var/new_language = input(usr, "Pick a language to convert messages to.", "Language Conversion") as null|anything in nttc.valid_languages
			if(!new_language)
				return
			if(new_language == "--DISABLE--")
				nttc.setting_language = null
				to_chat(usr, "<span class='notice'>Language conversion disabled.</span>")
			else
				nttc.setting_language = new_language
				to_chat(usr, "<span class='notice'>Messages will now be converted to [new_language].</span>")

			log_action(usr, new_language == "--DISABLE--" ? "disabled NTTC language conversion" : "set NTTC language conversion to [new_language]", TRUE)

		// Imports and exports
		if(href_list["import"])
			var/json = input(usr, "Provide configuration JSON below.", "Load Config", nttc.nttc_serialize()) as message
			if(nttc.nttc_deserialize(json, usr.ckey))
				log_action(usr, "has uploaded a NTTC JSON configuration: [ADMIN_SHOWDETAILS("Show", json)]", TRUE)

		if(href_list["export"])
			usr << browse(nttc.nttc_serialize(), "window=save_nttc")

		// Set network ID
		if(href_list["network_id"])
			var/new_id = input(usr, "Please enter a new network ID", "Network ID", network_id)
			log_action(usr, "renamed core with ID [network_id] to [new_id]")
			to_chat(usr, "<span class='notice'>Device ID changed from <b>[network_id]</b> to <b>[new_id]</b>.</span>")
			network_id = new_id

	if(ui_tab == UI_TAB_LINKS)
		if(href_list["unlink"])
			var/obj/machinery/tcomms/relay/R = locate(href_list["unlink"])
			if(istype(R, /obj/machinery/tcomms/relay))
				var/confirm = alert("Are you sure you want to unlink this relay?\nID: [R.network_id]\nADDR: \ref[R]", "Relay Unlink", "Yes", "No")
				if(confirm == "Yes")
					log_action(usr, "has unlinked tcomms relay with ID [R.network_id] from tcomms core with ID [network_id]", TRUE)
					R.Reset()
			else
				to_chat(usr, "<span class='alert'><b>ERROR:</b> Relay not found. Please file an issue report.</span>")

		if(href_list["change_password"])
			var/new_password = input(usr, "Please enter a new password","New Password", link_password)
			log_action(usr, "has changed the password on core with ID [network_id] from [link_password] to [new_password]")
			to_chat(usr, "<span class='notice'>Successfully changed password from <b>[link_password]</b> to <b>[new_password]</b>.</span>")
			link_password = new_password

	if(ui_tab == UI_TAB_FILTER)
		if(href_list["add_filter"])
			// This is a stripped input because I did NOT come this far for this system to be abused by HTML injection
			var/name_to_add = stripped_input(usr, "Enter a name to add to the filtering list", "Name Entry")
			if(name_to_add == "")
				return
			if(name_to_add in nttc.filtering)
				to_chat(usr, "<span class='alert'><b>ERROR:</b> User already in filtering list.</span>")
			else
				nttc.filtering |= name_to_add
				log_action(usr, "has added [name_to_add] to the NTTC filter list on core with ID [network_id]", TRUE)
				to_chat(usr, "<span class='notice'>Successfully added <b>[name_to_add]</b> to the NTTC filtering list.</span>")


		if(href_list["remove_filter"])
			var/name_to_remove = href_list["remove_filter"]
			if(!(name_to_remove in nttc.filtering))
				to_chat(usr, "<span class='alert'><b>ERROR:</b> Name does not exist in filter list. Please file an issue report.</span>")
			else
				var/confirm = alert(usr, "Are you sure you want to remove [name_to_remove] from the filtering list?", "Confirm Removal", "Yes", "No")
				if(confirm == "Yes")
					nttc.filtering -= name_to_remove
					log_action(usr, "has removed [name_to_remove] from the NTTC filter list on core with ID [network_id]", TRUE)
					to_chat(usr, "<span class='notice'>Successfully removed <b>[name_to_remove]</b> from the NTTC filtering list.</span>")


	// Hack to speed update the nanoUI
	SSnanoui.update_uis(src)

#undef UI_TAB_CONFIG
#undef UI_TAB_LINKS
#undef UI_TAB_FILTER
