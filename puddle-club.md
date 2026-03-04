# Puddle Club

## Executive summary

Puddle Club is an iOS app that automatically detects screenshots in the user's photo library, processes them on-device (OCR, entity extraction) and via OpenAI (semantic classification, tagging, action suggestions), and organizes them into searchable collections called Puddles. The core value prop: capture anything by screenshotting it, let the app do the rest.

---

## What it is

- A personal taste intelligence system built entirely from the user's screenshot library
- Not a recommendation engine — a mirror that reflects the user's existing aesthetic sensibility back to them
- Gets smarter over time as more screenshots are added — compounding value the longer you use it

## How it works

- On onboarding, user grants access to their Screenshots album via PhotoKit
- Vision framework runs on-device OCR pass on all screenshots — text extraction, basic classification
- Extracted text and compressed images are sent to an AI vision model (~~Claude or~~ GPT) for semantic interpretation
- Model identifies content type, entities, visual patterns, recurring motifs, and aesthetic qualities across the corpus
- Results are stored locally and indexed — building a personal taste profile over time
- New screenshots are processed in the background and continuously added to the profile

## What the taste graph knows

- Content categories (food, music, travel, design, fashion, products, etc.)
- Named entities (restaurants, artists, hotels, brands, locations)
- Visual patterns (color palettes, composition styles, lighting, typographic preferences)
- Implicit signals (things saved multiple times, things saved at night, things never acted on)
- Aesthetic qualities (e.g. "inhabited rather than designed", "melancholy with good production")
- Temporal patterns (what you save in different seasons, how taste evolves over time)

## The chat interface

- User can query their taste graph conversationally
- Queries can be practical: "I'm going to Copenhagen for four days, what should I do?"
- Queries can be exploratory: "What kind of music do I actually like?"
- Queries can be professional: "What in my library feels like quiet luxury without being cold?"
- Responses are calibrated to the user's specific taste profile — not generic recommendations
- Each response references actual content from the user's library as evidence

## Tenative technical considerations

- On-device Vision framework for initial OCR — free, private, fast
- AI vision model (~~Claude~~ / GPT) for semantic interpretation
- Text-rich screenshots: Vision OCR → API with text only
- Image-dominant screenshots: API with image directly (food, architecture, fashion)
- Local storage for taste profile — privacy preserving, no raw images sent to cloud unnecessarily
- Background processing via BGProcessingTask to avoid blocking UI

---

## Tech stack

- Swift / SwiftUI — modern, declarative UI
- SwiftData — persistence (iOS 17+, clean API, first-class SwiftUI integration)
- Vision framework — on-device OCR (VNRecognizeTextRequest)
- NaturalLanguage framework — entity tagging (NLTagger)
- Photos framework — library access, screenshot detection via PHAssetMediaSubtype.photoScreenshot
- OpenAI API — chat completions via URLSession (no third-party SDK)
- MusicKit — Apple Music playback actions
- EventKit — calendar actions

---

## Views

### Home

### Detail

---

## User stories

### Maya's User Journey [Taste Graph]

#### The User

**Maya, 34. Senior designer at a tech company. Lives in Atlanta. Travels frequently.**

Maya has 4,200 screenshots on her phone. Restaurants she meant to try, albums she heard at a dinner party, hotels from travel articles, furniture she keeps coming back to, fashion she admires but wouldn't wear. She knows her taste is specific but couldn't write it down. When people ask for recommendations she freezes — not because she doesn't have opinions but because they live in her body, not in words.

She downloads the app after seeing it on someone's story.

#### Onboarding

The app asks for access to her Screenshots album. No lengthy questionnaire, no "pick five things you like."

The water shader effect plays as it processes — unhurried, almost meditative. It doesn't feel like a loading screen, it feels like something is actually happening.

#### First Moment of Recognition

A few days later she gets a notification. Not a badge, not an alert — a single line:

> > _"We think we know you a little now."_

She opens the app. There's no dashboard, no graph, no list of inferred interests. Just a visual collection — her screenshots, reorganized in a way that feels different. Things she saved years apart are suddenly next to each other and it makes sense. A hotel in Lisbon she saved in 2021 is adjacent to a restaurant interior she saved last month. Same light. Same feeling. She didn't know those two things were connected until right now.

Below the collection, a single line of text:

> > _"You're drawn to spaces that feel inhabited rather than designed."_

She stares at that for a while. It's right.

#### First Useful Moment

A few days later she's planning a long weekend in New York. She opens the app and types:

> > _"I'm going to New York for three days in April. What should I do?"_

The response isn't a listicle. It's more like a well-traveled friend who has been paying attention:

> > _"Based on what you save, you'd probably skip the obvious stuff. You've screenshotted Superiority Burger twice and a lot of natural wine bars. You're drawn to neighborhoods that feel like they're in the middle of changing — you might find Ridgewood more interesting than the West Village right now. You saved a photo of the Noguchi Museum two years ago and never went — it's worth revisiting that intention."_

She goes to Ridgewood. It's exactly right.

#### The Compounding Value

Three months in the app knows her better than it did on day one. Every new screenshot adds signal. She notices she's stopped saving things randomly — she's more intentional now, almost like she's in a conversation with something that's listening.

She uses it before every trip. Before client presentations when she needs to articulate a visual direction. When she's trying to explain to a friend why she doesn't like a restaurant everyone loves.

She realizes at some point that it's not really a screenshot app anymore. It's the closest thing to an externalized version of her own taste that she's ever had.

#### The Unexpected Use

Eight months in she's working on a pitch for a new client — a boutique hotel group that can't quite articulate their brand direction. She opens the app and types:

> > _"What in my library feels like quiet luxury without being cold?"_

It pulls 23 images from across four years of saving. She puts them in a deck. The client says it's the best brief they've ever received.

#### The Core Insight

The product doesn't tell Maya what to like. It shows her what she already likes — more clearly than she could see it herself. That's the difference between a recommendation engine and a taste graph. One pushes content at you. The other holds up a mirror.

---

### James's User Journey [Taste Graph]

#### The User

**James, 29. Account manager at a logistics company. Lives in Chicago. Screenshots constantly, thinks about it never.**

James has 6,800 screenshots. He couldn't tell you why. Memes, obviously. But also: a lot of food. Concert announcements he never acted on. Shoes. Architecture he passed while scrolling at midnight. Cars. A surprising number of book covers he's never read. He doesn't think of himself as someone with refined taste. He thinks of himself as someone who is bad at follow-through.

His girlfriend uses the app and shows him something it said about her. He downloads it mostly out of curiosity.

#### Onboarding

Same experience as Maya. Access granted. Water effect. No questionnaire.

He forgets about it almost immediately.

#### First Moment of Recognition

Two weeks later he's bored on his lunch break and opens it. The app has been quietly working.

His screenshots are reorganized and there's a lot of them but something is different — the chaos is gone. It doesn't feel like a library. It feels more like flipping through a magazine that was made specifically for him.

He scrolls for longer than he expected.

Then he sees a line of text the app generated:

> > _"You save a lot of things at night that you forget about by morning. There's a version of you in here that has pretty strong opinions."_

He laughs out loud at his desk. Shows it to a coworker.

#### First Useful Moment

His college roommate is getting married in New Orleans in the fall. Group chat is trying to plan the bachelor party. Everyone is throwing out the same obvious ideas.

James opens the app almost as a joke:

> > _"Bachelor party in New Orleans. Four guys. We're not doing Bourbon Street."_

The app responds:

> > _"You've saved a lot of late night food content — the kind of places that don't take reservations and don't have a social media presence. You've also saved three separate things related to jazz without ever acting on any of them, which suggests you're interested but don't know where to start. New Orleans is actually the right place for that. You'd probably have a better time in the Marigny than the French Quarter. Bacchanal Wine comes up in your library twice."_

He screenshots the response. Sends it to the group chat.

They go to Bacchanal on night two. It becomes the story everyone tells about the trip.

#### The Compounding Value

James starts using it differently than Maya. Less for planning, more for the conversation. He asks it things he wouldn't google because they feel too vague:

> > _"I feel like my apartment looks fine but something is off."_

> > _"I keep saving the same kind of jacket in different colors — should I just buy one."_

> > _"What kind of music do I actually like."_

That last one surprises him. The app pulls his concert screenshots, the album art he saved, the playlists he screenshotted from other people's stories:

> > _"You save a lot of artists that fit loosely under the umbrella of melancholy with good production. Phoebe Bridgers, Sampha, that Nick Drake screenshot from 2022. You've never saved anything with a drop. You might actually hate clubs but have never said it out loud."_

He reads it twice.

Sends it to his girlfriend. She replies: _"I've been trying to tell you this for two years."_

#### The Unexpected Use

His company does a team offsite planning exercise where everyone shares three things that inspire them. He's dreaded this for weeks — it feels like the kind of thing that requires a personality he doesn't think he has.

He opens the app the night before:

> > _"I have to share three things that inspire me tomorrow at work. What would you pick from what you know about me?"_

The app pulls a photograph of a brutalist parking garage he saved in 2021, a clip of a chef working a line alone at 6am, and a screenshot of a Roger Federer quote about practice.

> > _"These three things keep coming back in different forms in your library. You seem to be drawn to people and things that are excellent at something most people don't notice."_

He uses exactly that in the meeting. His manager pulls him aside afterward and says it was the most interesting answer in the room.

He didn't know that about himself until the app said it.

#### The Core Insight

James never thought of himself as someone with taste. The app didn't give him taste — it showed him he already had it. That's the quieter, more universal version of Puddle Club's promise. It's not just for people who know what they like. It's for everyone who saves things without knowing why.
