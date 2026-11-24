// The Workbench's operations. Each takes bytes (a Uint8Array) and an argument, and returns
// { bytes, view } (or a promise of one): the bytes to hand to the next step, and optionally a view to
// show under the step (a frequency chart). The names and labels come from Intercept::Workbench, and
// the encodings must match Intercept::Cipher exactly: content is encoded in Ruby and decoded here.
//
// Nothing here knows any answer. It only transforms what the player has already been given.

const encoder = new TextEncoder()
const decoder = new TextDecoder("utf-8")
const latin1 = new TextDecoder("latin1")

export const bytesFromText = (text) => encoder.encode(text)
export const textFromBytes = (bytes) => decoder.decode(bytes)

export function hexFromBytes(bytes, separator = "") {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(separator)
}

function bytesFromHex(text, what = "text") {
  const hex = text.replace(/[^0-9a-fA-F]/g, "")
  if (hex.length === 0) throw new Error(`There's no hex in the ${what}.`)
  if (hex.length % 2 === 1) throw new Error(`The ${what} has an odd number of hex digits.`)
  return Uint8Array.from(hex.match(/../g), (pair) => parseInt(pair, 16))
}

const result = (bytes, view = null) => ({ bytes, view })

// --- Encodings -------------------------------------------------------------------------------

function fromBase64(bytes) {
  const text = textFromBytes(bytes).replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "")
  if (!/^[A-Za-z0-9+/]*$/.test(text) || text.length % 4 === 1) throw new Error("That isn't valid Base64.")

  const binary = atob(text + "=".repeat((4 - (text.length % 4)) % 4))
  return result(Uint8Array.from(binary, (char) => char.charCodeAt(0)))
}

function toBase64(bytes) {
  let binary = ""
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000))
  }
  return result(bytesFromText(btoa(binary)))
}

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

function fromBase32(bytes) {
  const text = textFromBytes(bytes).toUpperCase().replace(/[^A-Z2-7]/g, "")
  if (text.length === 0) throw new Error("There's no Base32 in the text.")

  const bits = Array.from(text, (char) => BASE32.indexOf(char).toString(2).padStart(5, "0")).join("")
  const out = new Uint8Array(Math.floor(bits.length / 8))
  for (let index = 0; index < out.length; index++) out[index] = parseInt(bits.slice(index * 8, index * 8 + 8), 2)
  return result(out)
}

// Byte for byte, like Ruby's CGI.unescape: "+" is a space, %XX is that byte (whether or not the bytes
// make UTF-8, since XOR output rarely does), and anything else, a stray "%" included, passes through.
function urlDecode(bytes) {
  const out = []
  const hex = (byte) => (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
  for (let index = 0; index < bytes.length; index++) {
    const byte = bytes[index]
    if (byte === 0x25 && hex(bytes[index + 1]) && hex(bytes[index + 2])) {
      out.push(parseInt(String.fromCharCode(bytes[index + 1], bytes[index + 2]), 16))
      index += 2
    } else {
      out.push(byte === 0x2b ? 0x20 : byte)
    }
  }
  return result(Uint8Array.from(out))
}

// --- Ciphers ---------------------------------------------------------------------------------

function shiftLetter(byte, shift) {
  const base = byte >= 65 && byte <= 90 ? 65 : byte >= 97 && byte <= 122 ? 97 : null
  return base === null ? byte : base + ((((byte - base + shift) % 26) + 26) % 26)
}

function parseShift(argument) {
  const shift = Number(argument)
  if (!Number.isInteger(shift) || shift < 1 || shift > 25) throw new Error("The shift is a whole number from 1 to 25.")
  return shift
}

function rot(bytes, argument) {
  const shift = parseShift(argument)
  return result(bytes.map((byte) => shiftLetter(byte, shift)))
}

function rotAll(bytes) {
  const lines = []
  for (let shift = 1; shift <= 25; shift++) {
    const text = textFromBytes(bytes.map((byte) => shiftLetter(byte, shift)))
    lines.push(`ROT ${String(shift).padStart(2)}: ${text.length > 160 ? `${text.slice(0, 160)}…` : text}`)
  }
  return result(bytesFromText(lines.join("\n")))
}

// Letters shift back by the key's letters in turn; anything else passes through without using one up.
function vigenereDecode(bytes, argument) {
  const key = String(argument ?? "").toUpperCase()
  if (!/^[A-Z]+$/.test(key)) throw new Error("The key is letters only, like CRUMPET.")

  const shifts = Array.from(key, (letter) => letter.charCodeAt(0) - 65)
  let index = 0
  return result(bytes.map((byte) => {
    const letter = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    if (!letter) return byte
    return shiftLetter(byte, -shifts[index++ % shifts.length])
  }))
}

function xorWith(bytes, key) {
  return result(bytes.map((byte, index) => byte ^ key[index % key.length]))
}

function xorText(bytes, argument) {
  const key = bytesFromText(String(argument ?? ""))
  if (key.length === 0) throw new Error("Type a key to XOR with.")
  return xorWith(bytes, key)
}

function xorHex(bytes, argument) {
  return xorWith(bytes, bytesFromHex(String(argument ?? ""), "key"))
}

// --- Analysis --------------------------------------------------------------------------------

function frequency(bytes) {
  const counts = new Array(26).fill(0)
  for (const byte of bytes) {
    if (byte >= 65 && byte <= 90) counts[byte - 65]++
    else if (byte >= 97 && byte <= 122) counts[byte - 97]++
  }
  const total = counts.reduce((sum, count) => sum + count, 0)
  const rows = counts.map((count, index) => ({ label: String.fromCharCode(65 + index), count, total }))
  return result(bytes, { kind: "frequency", rows, max: Math.max(1, ...counts) })
}

function findAll(bytes, argument) {
  let pattern
  try {
    pattern = new RegExp(String(argument ?? ""), "g")
  } catch {
    throw new Error("That pattern isn't a valid regular expression.")
  }
  if (!argument) throw new Error("Type a pattern to find.")

  const matches = Array.from(textFromBytes(bytes).matchAll(pattern), (match) => match[1] ?? match[0])
  if (matches.length === 0) throw new Error("Nothing matches that pattern.")
  return result(bytesFromText(matches.join("")))
}

function strings(bytes) {
  const runs = latin1.decode(bytes).match(/[\x20-\x7e]{4,}/g) || []
  return result(bytesFromText(runs.join("\n")))
}

// --- Forensics -------------------------------------------------------------------------------

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
const isPng = (bytes) => PNG_SIGNATURE.every((byte, index) => bytes[index] === byte)
const isPdf = (bytes) => latin1.decode(bytes.subarray(0, 5)) === "%PDF-"

function pngChunks(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const chunks = []
  let offset = 8
  while (offset + 8 <= bytes.length) {
    const length = view.getUint32(offset)
    const type = latin1.decode(bytes.subarray(offset + 4, offset + 8))
    chunks.push({ type, data: bytes.subarray(offset + 8, offset + 8 + length) })
    offset += 12 + length
    if (type === "IEND") break
  }
  return chunks
}

const TIFF_TAGS = {
  0x010e: "Description", 0x010f: "Camera make", 0x0110: "Camera model", 0x0131: "Software",
  0x0132: "Taken", 0x013b: "Artist", 0x8298: "Copyright"
}
const TYPE_SIZES = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 }

// Reads one IFD of a TIFF structure (as EXIF is) into { tag: value }.
function readIfd(view, offset, littleEndian) {
  const values = {}
  const count = view.getUint16(offset, littleEndian)
  for (let index = 0; index < count; index++) {
    const entry = offset + 2 + index * 12
    const tag = view.getUint16(entry, littleEndian)
    const type = view.getUint16(entry + 2, littleEndian)
    const length = view.getUint32(entry + 4, littleEndian)
    const size = (TYPE_SIZES[type] || 1) * length
    const at = size <= 4 ? entry + 8 : view.getUint32(entry + 8, littleEndian)

    if (type === 2) {
      values[tag] = latin1.decode(new Uint8Array(view.buffer, view.byteOffset + at, length)).replace(/\0+$/, "")
    } else if (type === 3 || type === 4) {
      const read = (i) => (type === 3 ? view.getUint16(at + i * 2, littleEndian) : view.getUint32(at + i * 4, littleEndian))
      values[tag] = length === 1 ? read(0) : Array.from({ length }, (_, i) => read(i))
    } else if (type === 5) {
      values[tag] = Array.from({ length }, (_, i) => view.getUint32(at + i * 8, littleEndian) / view.getUint32(at + i * 8 + 4, littleEndian))
    }
  }
  return values
}

function gpsLine(degrees, reference) {
  if (!Array.isArray(degrees) || degrees.length < 3) return null
  const [d, m, s] = degrees
  const decimal = d + m / 60 + s / 3600
  return `${decimal.toFixed(5)}° ${reference} (${d}° ${m}′ ${s.toFixed(1)}″ ${reference})`
}

function exifLines(data) {
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength)
  const littleEndian = view.getUint16(0) === 0x4949
  const ifd0 = readIfd(view, view.getUint32(4, littleEndian), littleEndian)
  const lines = Object.entries(TIFF_TAGS).filter(([tag]) => ifd0[tag] !== undefined).map(([tag, name]) => `${name}: ${ifd0[tag]}`)

  if (ifd0[0x8825] !== undefined) {
    const gps = readIfd(view, ifd0[0x8825], littleEndian)
    const latitude = gpsLine(gps[2], gps[1] || "N")
    const longitude = gpsLine(gps[4], gps[3] || "E")
    if (latitude) lines.push(`GPS latitude: ${latitude}`)
    if (longitude) lines.push(`GPS longitude: ${longitude}`)
  }
  return lines
}

function pngMetadata(bytes) {
  const lines = []
  for (const { type, data } of pngChunks(bytes)) {
    if (type === "IHDR") {
      const view = new DataView(data.buffer, data.byteOffset, data.byteLength)
      lines.push(`Image: ${view.getUint32(0)} × ${view.getUint32(4)} pixels`)
    } else if (type === "tEXt") {
      const split = data.indexOf(0)
      lines.push(`${latin1.decode(data.subarray(0, split))}: ${latin1.decode(data.subarray(split + 1))}`)
    } else if (type === "iTXt") {
      // keyword \0 compression-flag compression-method language \0 translated-keyword \0 text
      const keywordEnd = data.indexOf(0)
      const languageEnd = data.indexOf(0, keywordEnd + 3)
      const translatedEnd = data.indexOf(0, languageEnd + 1)
      if (data[keywordEnd + 1] === 0 && translatedEnd > 0) {
        lines.push(`${latin1.decode(data.subarray(0, keywordEnd))}: ${decoder.decode(data.subarray(translatedEnd + 1))}`)
      }
    } else if (type === "eXIf") {
      lines.push(...exifLines(data))
    }
  }
  return lines
}

function pdfMetadata(bytes) {
  const text = latin1.decode(bytes)
  const entries = text.matchAll(/\/(Title|Author|Subject|Keywords|Creator|Producer|CreationDate|ModDate)\s*\(((?:\\.|[^\\)])*)\)/g)
  return Array.from(entries, ([, name, value]) => `${name}: ${value.replace(/\\(.)/g, "$1")}`)
}

function metadata(bytes) {
  let lines
  if (isPng(bytes)) lines = pngMetadata(bytes)
  else if (isPdf(bytes)) lines = pdfMetadata(bytes)
  else throw new Error("This works on a file: load a photo or a document first.")

  return result(bytesFromText(lines.length ? lines.join("\n") : "No metadata found."))
}

// The lowest bit of each pixel's red, green and blue, in order, packed into bytes (highest bit first),
// up to the first zero byte. The picture must be decoded exactly, so no colour conversion.
async function lsb(bytes) {
  if (!isPng(bytes)) throw new Error("This works on a picture's pixels: load an image first.")

  const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/png" }), {
    colorSpaceConversion: "none", premultiplyAlpha: "none"
  })
  const canvas = document.createElement("canvas")
  canvas.width = bitmap.width
  canvas.height = bitmap.height
  const context = canvas.getContext("2d", { willReadFrequently: true })
  context.drawImage(bitmap, 0, 0)
  const pixels = context.getImageData(0, 0, bitmap.width, bitmap.height).data

  const out = []
  let byte = 0
  let bits = 0
  for (let index = 0; index < pixels.length && out.length < 8192; index++) {
    if (index % 4 === 3) continue // alpha
    byte = (byte << 1) | (pixels[index] & 1)
    if (++bits === 8) {
      if (byte === 0) break
      out.push(byte)
      byte = 0
      bits = 0
    }
  }
  return result(Uint8Array.from(out))
}

export const OPERATIONS = {
  from_base64: fromBase64,
  to_base64: toBase64,
  from_hex: (bytes) => result(bytesFromHex(textFromBytes(bytes))),
  to_hex: (bytes) => result(bytesFromText(hexFromBytes(bytes))),
  from_base32: fromBase32,
  url_decode: urlDecode,
  reverse: (bytes) => result(bytes.slice().reverse()),
  rot,
  rot_all: rotAll,
  vigenere_decode: vigenereDecode,
  xor: xorText,
  xor_hex: xorHex,
  frequency,
  find_all: findAll,
  strings,
  metadata,
  lsb
}
