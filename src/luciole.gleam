import gleam/bit_array
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import murmur3a
import simplifile

const eocd_signature = 0x06054b50

pub fn main() {
  // opens the epub file in question as a bit_array
  let assert Ok(file) = simplifile.read_bits(from: "example.epub")
  let file_bit_length = bit_array.byte_size(file)

  // grabs the last 65557 bytes of the epub file read -- this is where the eocd signature can be located!
  let eocd_byte_buffer =
    result.unwrap(bit_array.slice(file, file_bit_length, -{ 0xffff + 22 }), <<
      0,
    >>)

  let eocd_sig_bitarray =
    hex_to_bytes(
      prepend0(result.unwrap(int.digits(eocd_signature, 16), [])),
      <<>>,
    )

  let #(eocd, eocd_offset) = find_eocd(eocd_byte_buffer, eocd_sig_bitarray, 22)
  let cdh_offset_from_eocd = result.unwrap(bit_array.slice(eocd, 12, 4), <<>>)
  //let cdh_length = result.unwrap(bit_array.slice(eocd, 16, 4), <<>>)

  //io.print(bit_array.inspect(eocd) <> "\n")
  //io.print(bit_array.inspect(cdh_offset_from_eocd) <> "\n")

  let cdh_offset_int = bytes_to_int(cdh_offset_from_eocd, 0, 0)

  //io.print(int.to_string(file_bit_length) <> "\n")
  let total_cdh_from_eof_offset = eocd_offset + cdh_offset_int
  //io.print("\n" <> int.to_string(total_cdh_from_eof_offset) <> "\n")

  let cdh =
    result.unwrap(
      bit_array.slice(file, file_bit_length, -total_cdh_from_eof_offset),
      <<>>,
    )
  //io.debug(cdh)

  let centheaders = read_central_headers(cdh, total_cdh_from_eof_offset, [])
  find_local_headers(centheaders, file, [])
  //io.debug(hash_file(file))
  //let cdh =
  //  find_cdh(
  //    file,
  //    file_bit_length - total_cdh_from_eof_offset,
  //    bytes_to_int(cdh_length, 1, 0),
  //  )
  //io.debug(cdh)
}

/// find_eocd( buffer: BitArray, signature: BitArray, n = 22: int ) -> #(BitArray, Int)
/// This function finds the eocd in a bit array by recursively parsing through it backwards.
/// It takes in a signature as a BitArray instead of a hex int. To convert the int to a
/// BitArray, use hex_to_bytes() (see below.). The final argument is a tally for how far
/// back the beginning of the eocd is from the end of the file. 
fn find_eocd(
  eocd_buffer: BitArray,
  signature: BitArray,
  offset: Int,
) -> #(BitArray, Int) {
  //let signature = 0x06054b50
  let recursive_length = bit_array.byte_size(eocd_buffer)
  let compare_to_sig =
    result.unwrap(bit_array.slice(eocd_buffer, recursive_length - 22, 22), <<0>>)

  case bit_array.starts_with(compare_to_sig, signature) {
    True -> #(compare_to_sig, offset)
    False ->
      find_eocd(
        result.unwrap(bit_array.slice(eocd_buffer, 0, recursive_length - 1), <<
          0,
        >>),
        signature,
        offset + 1,
      )
  }
}

fn hex_to_bytes(hex_list: List(Int), return_bit_array: BitArray) -> BitArray {
  let _return_array = case hex_list {
    [hex1, hex2, ..rest] ->
      hex_to_bytes(
        rest,
        bit_array.concat([
          <<result.unwrap(int.undigits([hex1, hex2], 16), 0)>>,
          return_bit_array,
        ]),
      )
    [] -> return_bit_array
    [_] -> return_bit_array
  }
}

fn prepend0(hex_list: List(Int)) -> List(Int) {
  let length = list.length(hex_list)
  case length % 2 {
    1 -> [0, ..hex_list]
    _ -> hex_list
  }
}

/// bytes_to_int(BitArray, power = 0, value = 0)
fn bytes_to_int(bitarray: BitArray, power: Int, value: Int) -> Int {
  //pow must be a float
  let calc_value = fn(val, pow) {
    val * { float.round(result.unwrap(int.power(256, pow), 0.0)) }
  }

  let first_byte =
    result.unwrap(
      int.base_parse(
        bit_array.base16_encode(
          result.unwrap(bit_array.slice(bitarray, 0, 1), <<1>>),
        ),
        16,
      ),
      0,
    )
  let rest_of_array =
    result.unwrap(
      bit_array.slice(bitarray, 1, bit_array.byte_size(bitarray) - 1),
      <<>>,
    )

  case bit_array.byte_size(bitarray) {
    1 -> value
    _ ->
      bytes_to_int(
        rest_of_array,
        power + 1,
        value + calc_value(first_byte, int.to_float(power)),
      )
  }
}

pub type CentralRecord {
  CentralRecord(
    location: Int,
    header: BitArray,
    version: BitArray,
    version_extract: BitArray,
    bit_flag: BitArray,
    compression_method: BitArray,
    last_modified_time: BitArray,
    last_modified_date: BitArray,
    crc_32: BitArray,
    compressed_size: BitArray,
    uncompressed_size: BitArray,
    file_name_length: BitArray,
    extra_field_length: BitArray,
    file_comment_length: BitArray,
    disk_number_start: BitArray,
    internal_attribute: BitArray,
    external_attributes: BitArray,
    relative_offset: BitArray,
    file_name: BitArray,
    extra_field: BitArray,
    file_comment: BitArray,
  )
}

/// read_central_headers(bit_array, offset, []) 
/// make sure that the bit_array begins at the FIRST CENTRAL HEADER, and terminates at the end of the bitstream.
/// the offset is the distance from the first central header to the end of the bitstream, and the final argument
/// is an empty list that is returned. 
/// 
/// Can probably reduce some processing time by reading the associated file at the same time as this.
fn read_central_headers(
  bitarray: BitArray,
  header_offset: Int,
  info: List(CentralRecord),
) -> List(CentralRecord) {
  let record =
    CentralRecord(
      location: header_offset,
      header: result.unwrap(bit_array.slice(bitarray, 0, 4), <<>>),
      version: result.unwrap(bit_array.slice(bitarray, 4, 2), <<>>),
      version_extract: result.unwrap(bit_array.slice(bitarray, 6, 2), <<>>),
      bit_flag: result.unwrap(bit_array.slice(bitarray, 8, 2), <<>>),
      compression_method: result.unwrap(bit_array.slice(bitarray, 10, 2), <<>>),
      last_modified_time: result.unwrap(bit_array.slice(bitarray, 12, 2), <<>>),
      last_modified_date: result.unwrap(bit_array.slice(bitarray, 14, 2), <<>>),
      crc_32: result.unwrap(bit_array.slice(bitarray, 16, 4), <<>>),
      compressed_size: result.unwrap(bit_array.slice(bitarray, 20, 4), <<>>),
      uncompressed_size: result.unwrap(bit_array.slice(bitarray, 24, 4), <<>>),
      file_name_length: result.unwrap(bit_array.slice(bitarray, 28, 2), <<>>),
      extra_field_length: result.unwrap(bit_array.slice(bitarray, 30, 2), <<>>),
      file_comment_length: result.unwrap(bit_array.slice(bitarray, 32, 2), <<>>),
      disk_number_start: result.unwrap(bit_array.slice(bitarray, 34, 2), <<>>),
      internal_attribute: result.unwrap(bit_array.slice(bitarray, 36, 2), <<>>),
      external_attributes: result.unwrap(bit_array.slice(bitarray, 38, 4), <<>>),
      relative_offset: result.unwrap(bit_array.slice(bitarray, 42, 4), <<>>),
      file_name: <<>>,
      extra_field: <<>>,
      file_comment: <<>>,
    )
  let namelength = bytes_to_int(record.file_name_length, 0, 0)
  let extrafield = bytes_to_int(record.extra_field_length, 0, 0)
  let filecomment = bytes_to_int(record.file_comment_length, 0, 0)
  let new_record =
    CentralRecord(
      ..record,
      file_name: result.unwrap(bit_array.slice(bitarray, 46, namelength), <<>>),
      extra_field: result.unwrap(
        bit_array.slice(bitarray, 46 + namelength, extrafield),
        <<>>,
      ),
      file_comment: result.unwrap(
        bit_array.slice(bitarray, 46 + namelength + extrafield, filecomment),
        <<>>,
      ),
    )
  let nextarray =
    result.unwrap(
      bit_array.slice(
        bitarray,
        46 + namelength + extrafield + filecomment,
        bit_array.byte_size(bitarray)
          - { 46 + namelength + extrafield + filecomment },
      ),
      <<>>,
    )
  //something is wrong with the indexing of each entry i believe! ie. CentralHeader.location
  // remember 3930 is the distance from EOF to the start of the first central header
  case bit_array.starts_with(nextarray, record.header) {
    True ->
      read_central_headers(
        nextarray,
        header_offset - { 46 + namelength + extrafield + filecomment },
        [new_record, ..info],
      )
    False -> [new_record, ..info]
  }
}

//will need to figure out what directories need to be created, and what files belong in those directories before writing to them.
//also even when i create teh directories manually it doesnt work?
fn find_local_headers(
  records: List(CentralRecord),
  file: BitArray,
  out: List(#(String, BitArray)),
) -> List(#(String, BitArray)) {
  //assumes unencrypted as per epub
  let #(first, rest) = list.split(records, 1)
  let firstrecord = result.unwrap(list.first(first), write_dummy_record())
  let filelength = bytes_to_int(firstrecord.uncompressed_size, 0, 0)
  io.debug(filelength)
  let index_of_local_header =
    //this is the broken part
    bit_array.byte_size(file)
    - { firstrecord.location + bytes_to_int(firstrecord.relative_offset, 0, 0) }
  io.debug(index_of_local_header)
  let file_name_length = bytes_to_int(firstrecord.file_name_length, 0, 0)
  io.debug(file_name_length)
  io.debug(
    result.unwrap(bit_array.slice(file, index_of_local_header + 28, 2), <<>>),
  )
  let extra_field_length =
    bytes_to_int(
      result.unwrap(bit_array.slice(file, index_of_local_header + 28, 2), <<>>),
      0,
      0,
    )
  io.debug(extra_field_length)
  let filedata =
    result.unwrap(
      bit_array.slice(
        file,
        index_of_local_header + 30 + file_name_length + extra_field_length,
        filelength,
      ),
      <<>>,
    )
  let file_name = result.unwrap(bit_array.to_string(firstrecord.file_name), "")
  let assert Ok(Nil) = simplifile.create_file("../testout/" <> file_name)
  let assert Ok(Nil) =
    simplifile.write_bits(to: "../testout/" <> file_name, bits: filedata)

  case list.length(rest) {
    0 -> [#(file_name, filedata), ..out]
    _ -> find_local_headers(rest, file, [#(file_name, filedata), ..out])
  }
}

fn hash_file(file: BitArray) -> Int {
  bit_array.base64_encode(file, False)
  |> murmur3a.hash_string(7)
  |> murmur3a.int_digest()
}

fn write_dummy_record() -> CentralRecord {
  let _record =
    CentralRecord(
      location: 0,
      header: <<>>,
      version: <<>>,
      version_extract: <<>>,
      bit_flag: <<>>,
      compression_method: <<>>,
      last_modified_time: <<>>,
      last_modified_date: <<>>,
      crc_32: <<>>,
      compressed_size: <<>>,
      uncompressed_size: <<>>,
      file_name_length: <<>>,
      extra_field_length: <<>>,
      file_comment_length: <<>>,
      disk_number_start: <<>>,
      internal_attribute: <<>>,
      external_attributes: <<>>,
      relative_offset: <<>>,
      file_name: <<>>,
      extra_field: <<>>,
      file_comment: <<>>,
    )
}
