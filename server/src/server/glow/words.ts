/**
 * Owner: C3. The code words a glow can show, hand-picked (C3-D1 in docs/DECISIONS.md).
 *
 * Both people see the same word, huge, on a screen in the same color, and may say it out loud
 * across a loud room ("Are you lantern?"). So every word is:
 *
 * - short and friendly: a thing, an animal, a food or a place, 3 to 9 lowercase letters;
 * - nothing romantic or suggestive (no flowers, sweets or pet names), nothing rude or slangy, and
 *   nothing that reads as a comment on someone's body;
 * - not a common first name, so nobody mistakes it for the other person's name (P6 spirit);
 * - not a color, so it never fights with the glow color ("Aqua" plus "lime");
 * - hard to mishear: no two words rhyme (same word after the first consonants), differ by one
 *   letter, or contain each other.
 *
 * tests/glow/words.test.ts checks all of that, so a later edit can't quietly break it.
 * `start_glow` takes this list and picks a word no active glow in the room uses with that color.
 * With 8 colors and 300 words, a room runs out only past 2,400 glows at once.
 *
 * Kept in alphabetical order, so a change is easy to review.
 */
// prettier-ignore
export const CODE_WORDS = [
  'abacus', 'acorn', 'almond', 'alpaca', 'anchor', 'anvil', 'arcade', 'atlas', 'attic', 'avocado',
  'backpack', 'badger', 'bagel', 'balloon', 'bamboo', 'banjo', 'banner', 'barrel', 'basket',
  'beacon', 'beagle', 'beetle', 'bicycle', 'bingo', 'biscuit', 'bison', 'bobcat', 'bobsled',
  'bonsai', 'boulder', 'boxwood', 'bracket', 'bramble', 'breeze', 'broccoli', 'bucket', 'buckle',
  'bugle', 'burrito', 'button', 'cabin', 'cable', 'cactus', 'camper', 'canoe', 'canyon', 'carousel',
  'cashew', 'castle', 'cedar', 'cello', 'chalet', 'cheddar', 'chimney', 'chipmunk', 'chowder',
  'cinnamon', 'circus', 'clover', 'cobweb', 'comet', 'compass', 'condor', 'cookbook', 'cosmos',
  'cottage', 'cowbell', 'crater', 'crayon', 'cricket', 'crouton', 'dewdrop', 'dolphin', 'domino',
  'dragonfly', 'drizzle', 'drumbeat', 'dynamo', 'easel', 'eclipse', 'falafel', 'falcon', 'fern',
  'ferret', 'fiddle', 'fiesta', 'finch', 'firefly', 'flamingo', 'flannel', 'flute', 'fossil',
  'fresco', 'gadget', 'galaxy', 'garlic', 'gazebo', 'gazelle', 'gecko', 'giraffe', 'glacier',
  'glider', 'goblet', 'gondola', 'gopher', 'granite', 'granola', 'gravel', 'guitar', 'hammock',
  'hamster', 'harbor', 'harp', 'hedgehog', 'helmet', 'hexagon', 'hiccup', 'hilltop', 'hummus',
  'iceberg', 'icicle', 'igloo', 'impala', 'inkwell', 'island', 'jigsaw', 'jukebox', 'jupiter',
  'kayak', 'kazoo', 'kestrel', 'kettle', 'keyboard', 'kite', 'kiwi', 'koala', 'ladle', 'lagoon',
  'lantern', 'lasagna', 'lemonade', 'lemur', 'llama', 'lobster', 'macaw', 'magnet', 'magpie',
  'mango', 'mantis', 'maple', 'marble', 'marlin', 'marmot', 'meadow', 'meerkat', 'meteor',
  'mongoose', 'monsoon', 'mosaic', 'narwhal', 'nebula', 'noodle', 'notebook', 'nutmeg', 'oasis',
  'oatmeal', 'ocelot', 'octopus', 'orbit', 'orca', 'orchard', 'origami', 'osprey', 'ostrich',
  'paddle', 'pagoda', 'pancake', 'panda', 'panther', 'papaya', 'paprika', 'parade', 'parcel',
  'parrot', 'parsley', 'peanut', 'pebble', 'pelican', 'pencil', 'penguin', 'pepper', 'piano',
  'piccolo', 'pinball', 'pinecone', 'pinwheel', 'pizza', 'planet', 'plankton', 'platypus', 'plaza',
  'polka', 'popcorn', 'porcupine', 'possum', 'postcard', 'potato', 'prairie', 'pretzel', 'puffin',
  'puzzle', 'pyramid', 'quartz', 'quasar', 'quill', 'quokka', 'radish', 'rainbow', 'raisin',
  'ravioli', 'reef', 'rhubarb', 'ribbon', 'risotto', 'robot', 'rocket', 'rowboat', 'ruler',
  'sailboat', 'sardine', 'satchel', 'saturn', 'scooter', 'seagull', 'seahorse', 'sequoia',
  'shamrock', 'shuttle', 'sketch', 'snail', 'snorkel', 'snowball', 'snowshoe', 'sparrow', 'spatula',
  'spinach', 'spiral', 'spruce', 'squash', 'stapler', 'starfish', 'stingray', 'submarine', 'summit',
  'tadpole', 'teacup', 'teapot', 'telescope', 'thimble', 'thistle', 'thunder', 'tiger',
  'tinsel', 'toboggan', 'tomato', 'tortilla', 'toucan', 'tractor', 'trolley', 'trombone', 'truffle',
  'trumpet', 'tuba', 'tugboat', 'tundra', 'turbine', 'turnip', 'turtle', 'ukulele', 'umbrella',
  'unicycle', 'vapor', 'violin', 'volcano', 'waffle', 'wagon', 'walnut', 'warbler', 'wasabi',
  'windmill', 'windsock', 'wombat', 'yeti', 'yodel', 'yogurt', 'yoyo', 'zebra', 'zeppelin', 'zigzag',
  'zucchini',
] as const;

export type CodeWord = (typeof CODE_WORDS)[number];
