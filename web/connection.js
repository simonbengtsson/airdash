const useCustomPeerJsServer = true
const versionCode = 1.0

export async function tryConnection(deviceCode) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject('Connection timed out. Make sure the device code is correct and try again.')
    }, 5000)

    const peer = getPeerjs()
    const connectionId = `flownio-airdash-${deviceCode}`
    const conn = peer.connect(connectionId)
    conn.on('open', async function () {
      conn.on('data', (data) => {
        console.log('data', data)
        const versionCheck = checkVersionCode(data.versionCode)
        if (versionCheck.mismatch) {
          return reject(versionCheck)
        }

        clearTimeout(timeout)

        peer.destroy()
        resolve({ deviceName: data.deviceName })
      })
    })
    conn.on('error', function (err) {
      console.log('err', err)
      reject(err)
    })
  })
}

function getPeerjs() {
  const options = useCustomPeerJsServer ? {
    host: 'peerjs.flown.io',
    path: '/myapp',
    secure: true
  } : null
  return new peerjs.Peer(options)
}

export async function sendPayload(payload, meta, activeDevice, setStatus) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject('Connection timed out. Make sure the device id is correct and try again.')
    }, 5000)

    if (!activeDevice) return

    const connectionId = `flownio-airdash-${activeDevice}`
    setStatus('Connecting...')
    console.log(`Sending ${meta} to ${connectionId}...`)

    const totalSize = payload.size || 0
    const batchSize = 1000000
    let batch = 0

    const peer = getPeerjs()
    const metadata = {
      filename: meta,
      batchSize,
      fileSize: payload.size || -1
    }
    const conn = peer.connect(connectionId, { metadata })
    conn.on('open', async function () {
      clearTimeout(timeout)
      setStatus(`Sending...`)
      setTimeout(_ => {
        // conn.send blocks thread so wait one tick to let the
        // status change go through
        conn.send({ data: payload.slice(batch * batchSize, (batch + 1) * batchSize), batch })
        batch++
      })
    })
    conn.on('data', async function (data) {
      const type = data && data.type

      console.log('send on data', data)
      const versionCheck = checkVersionCode(data.versionCode)
      if (versionCheck.mismatch) {
        resolve('version-mismatch');
        return setStatus(versionCheck.error)
      }

      if (type === 'connected') {
      } else if (type === 'done') {
        if (batchSize * batch >= totalSize) {
          setStatus('Sent ' + meta)
          resolve('done')
        } else {
          setStatus(`Sending ${batch + 1}/${Math.ceil(totalSize / batchSize)} MB...`)
          setTimeout(_ => {
            // conn.send blocks thread so wait one tick to let the
            // status change go through
            conn.send({ data: payload.slice(batch * batchSize, (batch + 1) * batchSize), batch })
            batch++
          })
        }
      } else {
        console.log('unknown message', data)
        setStatus('Unknown message ' + data)
        reject(data)
      }
    })
    conn.on('error', function (err) {
      console.log('err', err)
      setStatus(err)
      reject(err)
    })
  })
}

function checkVersionCode(desktopVersionCode) {
  const areSameVersion = desktopVersionCode === versionCode
  if (!areSameVersion) {
    const isDesktopHigher = desktopVersionCode > versionCode
    return {
      mismatch: true,
      error: isDesktopHigher ? 'Update web app' : 'Update Desktop app'
    }
  }

  return true;
}
