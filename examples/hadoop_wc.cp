# Based on https://github.com/NaaS/system/blob/master/naasferatu/front-end/hadoop*.naas

type hadoop_wc : record
  # FIXME not sure what a "vlen" is in that example -- i can understand that
  #       it's a variable length integer, so shall we just call it an integer?
  key_len : integer
    { signed = false,
    endianness = big,
    # "size" in bytes
    size = 2 }
  key : string
    { size = "hadoop_wc.key_len" }
  value : integer
    { signed = false,
    endianness = big,
    size = 4 }

# Remainder is based on https://github.com/NaaS/system/blob/master/crisp/flick/examples.fk

# FIXME iron the semicolon out -- shouldnt be needed when have no parameters
fun AllReady : ([type hadoop_wc/-] chans;) -> (boolean)
  for i in unordered chans
  initially acc = True:
    acc and not (peek(chans[i]) = None)

fun prepend_x_if_must : (acc : [<integer * type hadoop_wc>], b : boolean, x : <integer * type hadoop_wc>) -> ([<integer * type hadoop_wc>])
  if b: acc else: x :: acc

type indexed_wc : [<integer * type hadoop_wc>]

fun sort_on_word : (l : type indexed_wc) -> (type indexed_wc)
  # NOTE below rely on ">" to be extended in the obvious way to life the
  # ">" over words (strings) to work on values of type idx*wc.
  # FIXME make the above lifting explicit to get a full example.
  for x in l
  initially acc = []:
    if acc = []: [x]
    else:
      let sub_sorted =
        for y in acc
        initially sub_acc = <[], False, x>:
          # NOTE this is how i avoid using pattern matching
          let ys = sub_acc.ys
          let b = sub_acc.b
          let x = sub_acc.x
          if not b:
            if x > y: <y :: x :: ys, True, x>
            else: <y :: ys, b, x>
          else: <y :: ys, b, x>
      prepend_x_if_must (sub_sorted, x)

proc WordCount : ([type hadoop_wc/-] input, -/type hadoop_wc output)
  if AllReady(input):
    input.peek().sort_on_word().combine().consume(input) => output
  else: <>

# Sum together the occurrences of the smallest word
fun combine : (l : type indexed_wc) -> (<[integer] * type hadoop_wc>)
  let initial_value =
    let smallest_value = head (sorted)
    <[smallest_value.1], smallest_value.2>

  for p in tail (sorted)
  initially acc = initial_value:
    let idx = p.1
    let wc' = p.2
    if wc'.word = wc.word :
      let wc'' = wc with count = wc.count + wc'.count
      <idx :: idxs, wc''>
    else: <idxs, wc>

# We project out the word-count element in the tuple, and return it.
# As a side-effect, we consume a value from each input channel which
#  contributed to the result we produce.
fun consume : ([type hadoop_wc/-] input; ans : <[integer] * type hadoop_wc>) -> (type hadoop_wc)
  let idxs = l.1
  let wc = l.2
  for i in idxs:
    read(input[i])
  wc
