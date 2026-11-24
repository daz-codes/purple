# Builds the files the Forensics missions hand out: photos with metadata or hidden bits, a document
# with tell-tale properties, and a resolver log. Plain Ruby, no gems, and deterministic, so running it
# again gives the same bytes. Run it after changing anything here, and commit what it writes:
#
#   ruby script/forensics_files.rb
#
# Every picture is drawn here (no real photos), and every place, person and domain is fictional. The
# GPS coordinates point at open sea, where Puffin Point would be if it existed.
#
# The bits hidden in a picture follow the Workbench's "Hidden bits" operation exactly: the lowest bit
# of each pixel's red, green and blue in turn, packed highest bit first, ending with a zero byte.
require "zlib"
require "fileutils"

module ForensicsFiles
  ROOT = File.expand_path("../content/paths/forensics", __dir__)

  module_function

  # --- PNG -------------------------------------------------------------------------------------

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end

  # pixels: rows of [r, g, b]. extra_chunks go before the image data; trailer goes after the end.
  def png(pixels, extra_chunks: [], trailer: "".b)
    height = pixels.size
    width = pixels.first.size
    raw = pixels.map { |row| "\x00".b + row.flatten.pack("C*") }.join
    "\x89PNG\r\n\x1A\n".b +
      chunk("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
      extra_chunks.join +
      chunk("IDAT", Zlib::Deflate.deflate(raw, Zlib::BEST_COMPRESSION)) +
      chunk("IEND", "".b) +
      trailer.b
  end

  def text_chunk(keyword, text)
    chunk("tEXt", "#{keyword}\x00#{text}".b)
  end

  # A drawn harbour: sky, sea, a lighthouse and a jetty, with a little grain. Deterministic.
  def harbour(width, height, seed:)
    random = Random.new(seed)
    horizon = (height * 0.55).round
    Array.new(height) do |y|
      Array.new(width) do |x|
        r, g, b =
          if x.between?(width * 0.7, width * 0.74) && y.between?(horizon - height * 0.35, horizon)
            y < horizon - height * 0.3 ? [ 240, 210, 90 ] : (y / 6).even? ? [ 230, 60, 60 ] : [ 240, 240, 235 ]
          elsif y.between?(horizon - 3, horizon + 2) && x < width * 0.45
            [ 90, 70, 55 ]
          elsif y < horizon
            [ 120 + y * 60 / horizon, 150 + y * 50 / horizon, 210 - y * 20 / horizon ]
          else
            [ 30, 70 + (y - horizon) * 30 / (height - horizon), 110 + (y - horizon) * 40 / (height - horizon) ]
          end
        [ r, g, b ].map { |channel| (channel + random.rand(-6..6)).clamp(0, 255) }
      end
    end
  end

  # Hides a message in the lowest bit of each colour channel, in order, then a zero byte.
  def hide(pixels, message)
    bits = (message.b + "\x00".b).unpack1("B*").chars.map(&:to_i)
    channels = pixels.flatten(1)
    raise "message too long for the picture" if bits.size > channels.size * 3

    bits.each_with_index do |bit, index|
      pixel = channels[index / 3]
      pixel[index % 3] = (pixel[index % 3] & 0xFE) | bit
    end
    pixels
  end

  # --- EXIF (a TIFF structure, big-endian), for a PNG eXIf chunk ---------------------------------

  ASCII = 2
  LONG = 4
  RATIONAL = 5

  # entries: [tag, type, value] where value is a String (ASCII), an Integer (LONG) or an Array of
  # [numerator, denominator] (RATIONAL). Returns the IFD and its out-of-line data, laid out at offset.
  def ifd(entries, offset, next_ifd: 0)
    data_offset = offset + 2 + entries.size * 12 + 4
    table = [ entries.size ].pack("n")
    data = "".b
    entries.sort_by(&:first).each do |tag, type, value|
      bytes, count =
        case type
        when ASCII then [ value.b + "\x00".b, value.bytesize + 1 ]
        when LONG then [ [ value ].pack("N"), 1 ]
        when RATIONAL then [ value.flatten.pack("N*"), value.size ]
        end
      if bytes.bytesize <= 4
        table << [ tag, type, count ].pack("nnN") << bytes.ljust(4, "\x00".b)
      else
        table << [ tag, type, count, data_offset + data.bytesize ].pack("nnNN")
        data << bytes
        data << "\x00".b if data.bytesize.odd?
      end
    end
    table << [ next_ifd ].pack("N")
    table + data
  end

  # degrees as [d, m, s] with s in thousandths, to EXIF rationals.
  def dms(degrees, minutes, thousandths_of_seconds)
    [ [ degrees, 1 ], [ minutes, 1 ], [ thousandths_of_seconds, 1000 ] ]
  end

  def exif(tags, gps:)
    header = "MM\x00\x2A".b + [ 8 ].pack("N")
    gps_offset_placeholder = 0
    ifd0_entries = tags + [ [ 0x8825, LONG, gps_offset_placeholder ] ]
    ifd0 = ifd(ifd0_entries, 8)
    gps_offset = 8 + ifd0.bytesize
    ifd0 = ifd(tags + [ [ 0x8825, LONG, gps_offset ] ], 8)
    header + ifd0 + ifd(gps, gps_offset)
  end

  # --- PDF -------------------------------------------------------------------------------------

  def pdf(lines, info:, comment:)
    stream = "BT /F1 14 Tf 60 760 Td #{lines.map { |line| "(#{line}) Tj 0 -24 Td" }.join(" ")} ET"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< #{info.map { |key, value| "/#{key} (#{value})" }.join(" ")} >>"
    ]
    out = "%PDF-1.4\n% #{comment}\n".b
    offsets = objects.each_with_index.map do |body, index|
      offset = out.bytesize
      out << "#{index + 1} 0 obj\n#{body}\nendobj\n"
      offset
    end
    xref = out.bytesize
    out << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| out << format("%010d 00000 n \n", offset) }
    out << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R /Info #{objects.size} 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
  end

  # --- The files -------------------------------------------------------------------------------

  def write(track, name, bytes)
    path = File.join(ROOT, track, "files", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
    puts "#{path.delete_prefix("#{File.expand_path("..", __dir__)}/")} (#{bytes.bytesize} bytes)"
  end

  def run
    # Metadata: a photo whose EXIF says who took it and where (the fuel depot on the site list).
    write "metadata", "harbour-photo.png", png(
      harbour(160, 120, seed: 1),
      extra_chunks: [
        text_chunk("Comment", "Send to Major Fitch by Tuesday."),
        chunk("eXIf", exif(
          [ [ 0x010E, ASCII, "Harbour at dawn" ], [ 0x010F, ASCII, "Grizzle Optics" ], [ 0x0110, ASCII, "GX-9" ],
            [ 0x0132, ASCII, "2026:11:02 06:14:09" ], [ 0x013B, ASCII, "Lt. Ottilie Brack, Grizzlemark Signals" ] ],
          gps: [ [ 1, ASCII, "N" ], [ 2, RATIONAL, dms(61, 28, 55_668) ], [ 3, ASCII, "W" ], [ 4, RATIONAL, dms(23, 10, 28_524) ] ]
        ))
      ]
    )

    write "metadata", "visitor-rota.pdf", pdf(
      [ "Puffin Point visitor rota (draft)", "Tuesday: R. Ashby, Pier 3", "Wednesday: M. Okon, fuel depot",
        "Thursday: no visitors" ],
      info: { "Title" => "Puffin Point visitor rota - DRAFT", "Author" => "Sgt. Wilbur Cragg",
              "Creator" => "Grizzlemark Office Suite", "Producer" => "Grizzlemark Office Suite 4.2",
              "CreationDate" => "D:20261101093000" },
      comment: "TEAPOT: leave the printed copy in the old boathouse."
    )

    # Hidden pictures: one message in the low bits, one tacked on after the picture ends, and one in
    # the low bits that is itself Base64.
    write "hidden-pictures", "sentry-post.png",
      png(hide(harbour(200, 150, seed: 2), "TEAPOT: the sentry dog is called Biscuit. Bring ham."))
    write "hidden-pictures", "lighthouse-postcard.png",
      png(harbour(160, 120, seed: 3), trailer: "TEAPOT FALLBACK FREQUENCY 4.625 MHz. Listen on the hour.")
    write "hidden-pictures", "shingle-beach.png",
      png(hide(harbour(200, 150, seed: 4), [ "Boat pickup at 0215 from the shingle beach." ].pack("m0")))

    write "traffic-and-logs", "resolver-log.txt", resolver_log
  end

  # A DNS resolver's log: ordinary lookups, and one machine smuggling hex-encoded text out in the
  # names it looks up under kettle-weather.example.
  def resolver_log
    secret = "Sunday nights have only two guards at the fuel depot."
    labels = secret.unpack1("H*").scan(/.{1,30}/)
    ordinary = %w[ updates.puffinpoint.example mail.puffinpoint.example weather.puffinpoint.example
                   intranet.puffinpoint.example time.puffinpoint.example canteen.puffinpoint.example ]
    random = Random.new(5)
    lines = []
    seconds = 3 * 3600 + 40 * 60
    smuggled = 0
    while smuggled < labels.size || lines.size < 40
      seconds += random.rand(2..19)
      clock = format("%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
      if smuggled < labels.size && (lines.size % 3 == 1)
        lines << "#{clock} client 10.20.4.17 query A #{labels[smuggled]}.#{smuggled}.kettle-weather.example"
        smuggled += 1
      else
        client = "10.20.#{random.rand(1..9)}.#{random.rand(10..200)}"
        lines << "#{clock} client #{client} query #{%w[ A AAAA MX ].sample(random:)} #{ordinary.sample(random:)}"
      end
    end
    lines.join("\n") + "\n"
  end
end

ForensicsFiles.run if $PROGRAM_NAME == __FILE__
