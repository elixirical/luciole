import gleam/bit_array
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import simplifile

//pub type EPub

//@external(erlang, "Elixir.BUPE", "parse")
//pub fn parse(x: String) -> EPub

//@external(erlang, "zip", "unzip")
//pub fn list_dir(name: String) -> EPub

//@external(erlang, "Elixir.Unzip.LocalFile", "open")
//pub fn open(x: String) -> EPub

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

  //io.debug(eocd_byte_buffer)

  // this converts the signature to a bit array against which we can check to see if we've located the signature
  let eocd_sig_bitarray =
    hex_to_bytes(
      prepend0(result.unwrap(int.digits(eocd_signature, 16), [])),
      <<>>,
    )

  let #(eocd, eocd_offset) = find_eocd(eocd_byte_buffer, eocd_sig_bitarray, 0)
  let cdh_offset_from_eocd = result.unwrap(bit_array.slice(eocd, 12, 4), <<>>)

  io.print(bit_array.inspect(cdh_offset_from_eocd))

  let cdh_offset_int = bytes_to_int(cdh_offset_from_eocd, 1, 0)

  io.debug(cdh_offset_int)
  //0x0F44
  //io.debug(eocd_offset)
  //io.print(bit_array.inspect(eocd))
  //io.debug(bit_array.byte_size(eocd))
}

fn find_eocd(
  eocd_buffer: BitArray,
  signature: BitArray,
  offset: Int,
) -> #(BitArray, Int) {
  //let signature = 0x06054b50
  let recursive_length = bit_array.byte_size(eocd_buffer)
  io.debug(offset)
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

fn bytes_to_int(bitarray: BitArray, power: Int, value: Int) -> Int {
  //pow must be a float
  let calc_value = fn(val, pow) {
    val * { float.round(result.unwrap(int.power(16, pow), 0.0)) }
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
  io.print("\nfirst_byte: " <> int.to_string(first_byte) <> "\n")
  io.print(
    "bitarray_bytesize: "
    <> int.to_string(bit_array.byte_size(bitarray))
    <> "\n",
  )
  io.print("Power: " <> int.to_string(power))
  io.print(bit_array.inspect(rest_of_array))

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
