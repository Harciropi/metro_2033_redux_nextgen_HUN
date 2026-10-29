"""Approved spacing rules. Never edit placeholders, timing cues or legal credits."""
import re

USE_KEYS = {'$use', 'Copy of $use'}
USE_TEXT = 'A(z) <use>gombbal használhatsz tárgyakat.'
# Known composed UI fragments, invisible sentinel, aligned order tables.
KEEP = {'empty', '$trade_in', '$trade_in_plus', '$move_controls', 'menu_nomoney_prompt_3'}

def protected(key):
    return bool(re.search(r'credits|licen[cs]e|copyright', key, re.I)) or key in KEEP or key.startswith('faction_orders_')

def prose(text):
    # Keep indentation and line endings, normalize only spaces between words.
    text = re.sub(r'(?<=\S) {2,}(?=\S)', ' ', text)
    def ellipsis(match):
        prefix = text[:match.start()]
        # A new line or a text segment after a timing cue starts a new utterance.
        prefix = prefix.rsplit('\n', 1)[-1]
        beginning = not prefix.strip(' \t\r\"\'„“([{')
        return match[1] + ('' if beginning else ' ')
    return re.sub(r'(\.{3,}|…) *(?=[^\W_])', ellipsis, text, flags=re.UNICODE)

def transform(key, text):
    if key in USE_KEYS: return USE_TEXT
    if protected(key): return text
    pieces = re.split(r'(<[^>]*>)', text)
    pieces = [piece if n % 2 else prose(piece) for n, piece in enumerate(pieces)]
    result = ''.join(pieces)
    # Cue-adjacent spaces and blank timed subtitles can be functional.
    if '<time=' in text: return result
    # Retain deliberate list/menu indentation and line formatting.
    if re.match(r'^ +[-•]', text): return result.rstrip(' ')
    return result.strip(' ')
