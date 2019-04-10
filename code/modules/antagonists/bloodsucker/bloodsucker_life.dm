

// 		TO PLUG INTO LIFE:

// Cancel BLOOD life
// Cancel METABOLISM life   (or find a way to control what gets digested)
// Create COLDBLOODED trait (thermal homeostasis)

// 		EXAMINE
//
// Show as dead when...







/datum/antagonist/bloodsucker/proc/LifeTick() // Should probably run from life.dm, same as handle_changeling
	set waitfor = FALSE // Don't make on_gain() wait for this function to finish. This lets this code run on the side.



	var/notice_healing = FALSE
	while (owner && !AmFinalDeath()) // owner.has_antag_datum(ANTAG_DATUM_BLOODSUCKER) == src

		//
		//if (owner.current.stat != DEAD && !owner.current.has_trait(TRAIT_DEATHCOMA, "bloodsucker"))

		// Deduct Blood
		if (owner.current.stat == CONSCIOUS && !poweron_feed)
			AddBloodVolume(-0.2) // -.15 (before tick went from 10 to 30, but we also charge more for faking life now)

		// Heal
		if (HandleHealing(1))
			if (notice_healing == FALSE && owner.current.blood_volume > 0)
				to_chat(owner, "<span class='notice'>The power of your blood begins knitting your wounds...</span>")
				notice_healing = TRUE
		else if (notice_healing == TRUE)
			notice_healing = FALSE

		// Apply Low Blood Effects
		HandleStarving()

		// Death
		HandleDeath()

		// Standard Update
		//update_hud()

		// Wait before next pass
		sleep(10)//sleep(30)

	// Free my Vassals! (if I haven't yet)
	//FreeAllVassals()





/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//			BLOOD

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/datum/antagonist/bloodsucker/proc/AddBloodVolume(value)
	owner.current.blood_volume = CLAMP(owner.current.blood_volume + value, 0, maxBloodVolume)
	//update_hud()


/datum/antagonist/bloodsucker/proc/HandleFeeding(mob/living/carbon/target, mult=1)
	// mult: SILENT feed is 1/3 the amount

	var/blood_taken = min(feedAmount, target.blood_volume) * mult	// Starts at 15 (now 8 since we doubled the Feed time)
	target.blood_volume -= blood_taken

	// Simple Animals lose a LOT of blood, and take damage. This is to keep cats, cows, and so forth from giving you insane amounts of blood.
	if (!ishuman(target))
		target.blood_volume -= (blood_taken / max(target.mob_size, 0.1)) * 3.5 // max() to prevent divide-by-zero
		target.apply_damage_type(blood_taken / 3.5) // Don't do too much damage, or else they die and provide no blood nourishment.
		if (target.blood_volume <= 0)
			target.blood_volume = 0
			target.death(0)

	///////////
	// Shift Body Temp (toward Target's temp, by volume taken)
	owner.current.bodytemperature = ((owner.current.blood_volume * owner.current.bodytemperature) + (blood_taken * target.bodytemperature)) / (owner.current.blood_volume + blood_taken)
	// our volume * temp, + their volume * temp, / total volume
	///////////

	// Reduce Value Quantity
	if (target.stat == DEAD)	// Penalty for Dead Blood			<------ **** ALSO make drunk????!
		blood_taken /= 3
	if (!ishuman(target))		// Penalty for Non-Human Blood
		blood_taken /= 2
	//if (!iscarbon(target))	// Penalty for Animals (they're junk food)


	// Apply to Volume
	AddBloodVolume(blood_taken)

	// Reagents (NOT Blood!)
	if(target.reagents && target.reagents.total_volume)
		target.reagents.reaction(owner.current, INGEST, 1 / target.reagents.total_volume) // Run Reaction: what happens when what they have mixes with what I have?
		target.reagents.trans_to(owner.current, 1)	// Run transfer of 1 unit of reagent from them to me.

	// Blood Gulp Sound
	owner.current.playsound_local(null, 'sound/effects/singlebeat.ogg', 40, 1) // Play THIS sound for user only. The "null" is where turf would go if a location was needed. Null puts it right in their head.



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//			HEALING

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//
/datum/antagonist/bloodsucker/proc/HandleHealing(mult = 1)

	if (poweron_masquerade == TRUE || owner.current.AmStaked())
		return FALSE

	owner.current.adjustStaminaLoss(-1 * mult, 0)
	owner.current.adjustCloneLoss(-1 * mult, 0)
	owner.current.adjustBrainLoss(-1 * mult, 0)

	owner.current.setOxyLoss(0)
	owner.current.setToxLoss(0)

	// No Bleeding
	if (ishuman(owner.current))
		var/mob/living/carbon/human/H = owner.current
		H.bleed_rate = 0 // NOTE: This is done HERE, not in hande_healing_natural, because

	// Damage Heal: Do I have damage to ANY bodypart?
	if (iscarbon(owner.current))
		var/mob/living/carbon/C = owner.current
		var/costMult = 1 // Only goes down being in a coffin

		// BURN: Heal in Coffin while Fakedeath, or when damage above maxhealth (you can never fully heal fire)
		var/fireheal = 0
		if(istype(C.loc, /obj/structure/closet/crate/coffin) && C.has_trait(TRAIT_DEATHCOMA, "bloodsucker"))
			mult *= 3 // Increase multiplier if we're sleeping in a coffin.
			fireheal = min(C.getFireLoss(), regenRate / 2 * mult) // NOTE: Burn damage heals 5x quicker in Torpor (the only way we can be healing while dead)
			costMult = 0
		else
			// No Blood? Lower Mult
			if (owner.current.blood_volume <= 0)
				mult = 0.25
			// Crit from burn? Lower damage to maximum allowed.
			if (C.getFireLoss() > owner.current.getMaxHealth())
				fireheal = regenRate / 2 * mult
		// BRUTE: Always Heal
		var/bruteheal = min(C.getBruteLoss(), regenRate * mult)

		// Heal if Damaged
		if (bruteheal + fireheal > 0)
			to_chat(C, "<span class='warning'>TEST:[bruteheal] [fireheal] [mult] [costMult]</span>")


			// We have damage. Let's heal (one time)
			C.heal_overall_damage(bruteheal * mult, fireheal * mult)			//C.heal_overall_damage(bruteheal, fireheal) 					// Heal BRUTE / BURN in random portions throughout the body.
			// Pay Cost
			AddBloodVolume((bruteheal * -0.5 + fireheal * -1) / mult * costMult)		//AddBloodVolume((bruteheal * -0.5 + fireheal * -1) / mult)		// Costs blood to heal (but Mult doesn't affect it...you still pay the same)

			return TRUE

	return FALSE


/datum/antagonist/bloodsucker/proc/HandleHealing_Limbs()

	var/list/missing = owner.current.get_missing_limbs()
	if (missing.len)
		// 1) Find ONE Limb and regenerate it.
		var/targetLimb = pick(missing)
		owner.current.regenerate_limb(targetLimb, 0)		// regenerate_limbs() <--- If you want to EXCLUDE certain parts, do it like this ----> regenerate_limbs(0, list("head"))
		// 2) Limb returns Damaged
		var/obj/item/bodypart/L = owner.current.get_bodypart( targetLimb )
		L.brute_dam = 50
		to_chat(owner.current, "<span class='notice'>Your flesh knits as it regrows [L]!</span>")
		playsound(owner.current, 'sound/magic/demon_consume.ogg', 50, 1)
		// DONE! After regenerating a limb, we stop here.
		return TRUE

	// Cure Final Disabilities
	owner.current.cure_blind()
	owner.current.cure_husk()

	// Remove Embedded!
	var/mob/living/carbon/C = owner.current
	C.remove_all_embedded_objects()

	return FALSE

// I am hungry!
/datum/antagonist/bloodsucker/proc/HandleStarving()

	// High: 	Faster Healing
	// Med: 	Pale
	// Low: 	Twitch
	// V.Low:   Blur Vision
	// EMPTY:	Frenzy!

	// BLOOD_VOLUME_GOOD: [336]  Pale (handled in bloodsucker_integration.dm


	// BLOOD_VOLUME_BAD: [224]  Jitter
	if (owner.current.blood_volume < BLOOD_VOLUME_BAD && !prob(5))
		owner.current.Jitter(10)

	// BLOOD_VOLUME_SURVIVE: [122]  Blur Vision
	if (owner.current.blood_volume < BLOOD_VOLUME_BAD)
		owner.current.blur_eyes(10 - 10 * (owner.current.blood_volume / BLOOD_VOLUME_BAD))

	// Nutrition
	owner.current.nutrition = min(owner.current.blood_volume, NUTRITION_LEVEL_FED) // <-- 350  //NUTRITION_LEVEL_FULL



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//			DEATH

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/datum/antagonist/bloodsucker/proc/HandleDeath()

		// 	FINAL DEATH

	// Fire Damage? (above double health)
	if (owner.current.getFireLoss() >= owner.current.getMaxHealth() * 2)
		FinalDeath()
		return
	// Staked while "Temp Death" or Asleep
	if ((owner.current.IsSleeping() || owner.current.stat >= UNCONSCIOUS|| owner.current.blood_volume <= 0) && owner.current.AmStaked())
		FinalDeath()
		return
	// Not "Alive"?
	if (!owner.current || !isliving(owner.current) || isbrain(owner.current) || !get_turf(owner.current))
		FinalDeath()
		return
	// Missing Brain or Heart?

				// Disable Powers: Masquerade	* NOTE * This should happen as a FLAW!
				//if (stat >= UNCONSCIOUS)
				//	for (var/datum/action/bloodsucker/masquerade/P in powers)
				//		P.Deactivate()

		//	TEMP DEATH

	var/total_damage = owner.current.getBruteLoss() + owner.current.getFireLoss()
	// Died? Convert to Torpor (fake death)
	if (owner.current.stat >= DEAD)
		owner.current.fakedeath("bloodsucker")
		owner.current.add_trait(TRAIT_NODEATH,"bloodsucker")	// Without this, you'll just keep dying while you recover.
		owner.current.stat = UNCONSCIOUS
		owner.current.update_stat() //owner.current.stat = UNCONSCIOUS
		to_chat(owner, "<span class='danger'>Your immortal body will not yet relinquish your soul to the abyss.</span>")
		if (poweron_masquerade == TRUE)
			to_chat(owner, "<span class='warning'>Your wounds will not heal until you disable the <span class='boldnotice'>Masquerade</span> power.</span>")
	else
		if (total_damage <= owner.current.getMaxHealth() && owner.current.has_trait(TRAIT_DEATHCOMA, "bloodsucker"))
			owner.current.cure_fakedeath("bloodsucker")
			owner.current.remove_trait(TRAIT_NODEATH,"bloodsucker")
			owner.current.stat = SOFT_CRIT
			owner.current.update_stat() //owner.current.stat = CONSCIOUS
		// Fake Unconscious
		if (poweron_masquerade == TRUE && total_damage >= owner.current.getMaxHealth() - HEALTH_THRESHOLD_FULLCRIT)
			owner.current.Unconscious(20,1)

	//HEALTH_THRESHOLD_CRIT 0
	//HEALTH_THRESHOLD_FULLCRIT -30
	//HEALTH_THRESHOLD_DEAD -100

/datum/antagonist/bloodsucker/proc/AmFinalDeath()
 	return owner && owner.AmFinalDeath()

/datum/mind/proc/AmFinalDeath()
 	return !current || !isliving(current) || isbrain(current) || !get_turf(current) // NOTE: "isliving()" is not the same as STAT == CONSCIOUS. This is to make sure you're not a BORG (aka silicon)

/datum/antagonist/bloodsucker/proc/FinalDeath()

	playsound(get_turf(owner.current), 'sound/effects/tendril_destroyed.ogg', 60, 1)
	owner.current.drop_all_held_items()
	owner.current.unequip_everything()
	var/mob/living/carbon/C = owner.current
	C.remove_all_embedded_objects()

	// Free my Vassals!
	//FreeAllVassals()

	// Elders get Dusted
	if (vamptitle)
		owner.current.visible_message("<span class='warning'>[owner.current]'s skin crackles and dries, their skin and bones withering to dust. A hollow cry whips from what is now a sandy pile of remains.</span>", \
			 "<span class='userdanger'>Your soul escapes your withering body as the abyss welcomes you to your Final Death.</span>", \
			 "<span class='italics'>You hear a dry, crackling sound.</span>")
		owner.current.dust()
	// Fledglings get Gibbed
	else
		owner.current.visible_message("<span class='warning'>[owner.current]'s skin bursts forth in a spray of gore and detritus. A horrible cry echoes from what is now a wet pile of decaying meat.</span>", \
			 "<span class='userdanger'>Your soul escapes your withering body as the abyss welcomes you to your Final Death.</span>", \
			 "<span class='italics'>You hear a wet, bursting sound.</span>")
		owner.current.gib()



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//			HUMAN FOOD

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/mob/proc/CheckBloodsuckerEatFood(var/food_nutrition)
	if (!isliving(src))
		return
	var/mob/living/L = src
	if (!L.AmBloodsucker())
		return
	// We're a vamp? Try to eat food...
	var/datum/antagonist/bloodsucker/bloodsuckerdatum = mind.has_antag_datum(ANTAG_DATUM_BLOODSUCKER)
	bloodsuckerdatum.handle_eat_human_food(food_nutrition)


/datum/antagonist/bloodsucker/proc/handle_eat_human_food(var/food_nutrition) // Called from snacks.dm and drinks.dm
	if (!owner.current || !iscarbon(owner.current))
		return
	var/mob/living/carbon/C = owner.current

	// Remove Nutrition, Give Bad Food
	C.nutrition -= food_nutrition
	foodInGut += food_nutrition

	// Already ate some bad clams? Then we can back out, because we're already sick from it.
	if (foodInGut != food_nutrition)
		return
	// Haven't eaten, but I'm in a Human Disguise.
	else if (poweron_masquerade)
		to_chat(C, "<span class='notice'>Your stomach turns, but your Human Disguise keeps the food down...for now.</span>")

	// First Food

	// Keep looping until we purge. If we have activated our Human Disguise, we ignore the food. But it'll come up eventually...
	var/sickphase = 0
	while (foodInGut)

		// Wait an interval...
		sleep(100 + 50 * sickphase) // At intervals of 100, 150, and 200. (10 seconds, 15 seconds, and 20 seconds)

		// Died? Cancel
		if (C.stat == DEAD)
			return
		// Put up disguise? Then hold off the vomit.
		if (poweron_masquerade)
			if (sickphase > 0)
				to_chat(C, "<span class='notice'>Your stomach settles temporarily. You regain your composure...for now.</span>")
			sickphase = 0
			continue

		switch(sickphase)
			if (1)
				to_chat(C, "<span class='warning'>You feel unwell. You can taste ash on your tongue.</span>")
			if (2)
				to_chat(C, "<span class='warning'>Your stomach turns. Whatever you ate tastes of grave dirt and brimstone.</span>")
				C.Dizzy(15)
			if (3)
				to_chat(C, "<span class='warning'>You purge the food of the living from your viscera! You've never felt worse.</span>")
				C.vomit(foodInGut * 4, foodInGut * 2, 0)  // (var/lost_nutrition = 10, var/blood = 0, var/stun = 1, var/distance = 0, var/message = 1, var/toxic = 0)
				C.blood_volume = max(0, C.blood_volume - foodInGut * 2)
				C.Stun(rand(20,30))
				C.Dizzy(50)
				foodInGut = 0

		sickphase ++











