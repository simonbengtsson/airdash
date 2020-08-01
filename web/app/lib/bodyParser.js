
export async function parseFormData(request) {
  const bodyBlob = await request.clone().blob()
  const oneMb = 1000000
  if (bodyBlob.size < oneMb) {
    // formData() freezes tab or browser when body is too large
    let formData = await request.formData()
    const text = (formData.get('text') || formData.get('rawtext') || '').trim()
    if (text) {
      const preview = `"${text.substr(0, 16)}"`
      return { payload: text, meta: preview }
    }
  }

  const contentType = request.headers.get('Content-Type')
  const file = await findFileInBody(bodyBlob, contentType)
  return { payload: file, meta: file.name }
}

async function findFileInBody(bodyBlob, contentType) {
  let boundary = '--' + contentType.replace('multipart/form-data; boundary=', '')
  const endingBoundary = `\r\n${boundary}--\r\n`
  const endBoundarySize = (new TextEncoder().encode(endingBoundary)).length
  const { startPosition, filename} = await findFileInfo(bodyBlob, boundary)
  const fileBlob = bodyBlob.slice(startPosition, -endBoundarySize)
  return new File([fileBlob], filename)
}

async function findFileInfo(blob, boundary) {
  const decoder = new TextDecoder('utf-8')
  const { value } = await blob.stream().getReader().read()
  const str = decoder.decode(value)
  const parts = str.split(boundary + '\r\n')

  const filePart = parts.pop()
  const search = 'filename="'
  const start = filePart.indexOf(search) + search.length
  const end = filePart.indexOf('"', start)
  const encoded = filePart.substring(start, end)
  const filename = decodeURI(encoded)
  if (!filename) {
    throw new Error('Could not find file in form data')
  }
  let raw = parts.join(boundary + '\r\n') + boundary + '\r\n'
  raw += filePart.split('\r\n\r\n')[0] + '\r\n\r\n'
  const startPosition = new Blob([raw]).size
  return { startPosition, filename }
}