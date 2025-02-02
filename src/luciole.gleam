import epub
import gleam/bit_array
import gleam/int
import gleam/result
import murmur3a
import simplifile

const eocd_signature = 0x06054b50

pub fn main() {
  // opens the epub file in question as a bit_array
  let assert Ok(file) = simplifile.read_bits(from: "example.epub")
  let file_bit_length = bit_array.byte_size(file)

  let assert Ok(coverjpg) = simplifile.read_bits(from: "cover.jpeg")

  // grabs the last 65557 bytes of the epub file read -- this is where the eocd signature can be located!
  let eocd_byte_buffer =
    result.unwrap(bit_array.slice(file, file_bit_length, -{ 0xffff + 22 }), <<
      0,
    >>)

  let eocd_sig_bitarray =
    epub.hex_to_bytes(
      epub.prepend0(result.unwrap(int.digits(eocd_signature, 16), [])),
      <<>>,
    )

  let #(eocd, eocd_offset) =
    epub.find_eocd(eocd_byte_buffer, eocd_sig_bitarray, 22)
  let cdh_offset_from_eocd = result.unwrap(bit_array.slice(eocd, 12, 4), <<>>)
  //let cdh_length = result.unwrap(bit_array.slice(eocd, 16, 4), <<>>)

  //io.print(bit_array.inspect(eocd) <> "\n")
  //io.print(bit_array.inspect(cdh_offset_from_eocd) <> "\n")

  let cdh_offset_int = epub.bytes_to_int(cdh_offset_from_eocd, 0, 0)

  //io.print(int.to_string(file_bit_length) <> "\n")
  let total_cdh_from_eof_offset = eocd_offset + cdh_offset_int
  //io.print("\n" <> int.to_string(total_cdh_from_eof_offset) <> "\n")

  let cdh =
    result.unwrap(
      bit_array.slice(file, file_bit_length, -total_cdh_from_eof_offset),
      <<>>,
    )
  //io.debug(cdh)

  let centheaders =
    epub.read_central_headers(cdh, total_cdh_from_eof_offset, [])
  epub.find_local_headers(centheaders, file, [], coverjpg)
  //io.debug(hash_file(file))
  //let cdh =
  //  find_cdh(
  //    file,
  //    file_bit_length - total_cdh_from_eof_offset,
  //    bytes_to_int(cdh_length, 1, 0),
  //  )
  //io.debug(cdh)
}

fn hash_file(file: BitArray) -> Int {
  bit_array.base64_encode(file, False)
  |> murmur3a.hash_string(7)
  |> murmur3a.int_digest()
}
