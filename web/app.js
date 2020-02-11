(async function() {
  try {
    await navigator.serviceWorker.register('./sw.js')
  } catch (err) {
    console.log('sw failed', err)
  }

  new Cleave('#connection-id', {
    delimiter: '-',
    blocks: [3, 3, 3],
    numericOnly: true
  });

  if (window.location.host.includes('localhost')) {
    document.querySelector('h1').textContent = 'AirDash Dev'
  }

  setupFileInput()
  setupDeviceId()
  setupInstallPrompt()
  await handleStoredFile()
})()

function setupInstallPrompt() {
  let deferredPrompt;
  document.querySelector('#android-install').addEventListener('click', () => {
    deferredPrompt.prompt();
  })
  window.addEventListener('beforeinstallprompt', (e) => {
    deferredPrompt = e;
  });
}

function getConnectionId() {
  return localStorage.getItem('connection-id') || ''
}

function setupFileInput() {
  document.querySelector('#file-input').onchange = (event) => {
    console.log('File picked', event.target.files[0].name)
    document.querySelector('#file-form').submit()
    setStatus('Preparing...')
  }
}

function setupDeviceId() {
  const connectionIdField = document.querySelector('#connection-id')
  connectionIdField.value = getConnectionId()
  connectionIdField.oninput = async event => {
    const newValue = event.target.value
    localStorage.setItem('connection-id', newValue)
    if (newValue.length === 11) {
      console.log('New connection id', newValue)
      try {
        setStatus('Connecting...')
        await tryConnection()
        setStatus('Ready')
      } catch(err) {
        setStatus(err)
      }
    } else {
      setStatus('Enter Device ID')
    }
  }
}

async function handleStoredFile() {
  const error = await localforage.getItem('error')
  const file = await localforage.getItem('file')
  if (error) {
    setStatus('Error: ' + error)
  } else if (file) {
    const filename = await localforage.getItem('filename') || 'unknown'
    try {
      await sendFile(file, filename)
    } catch (err) {
      setStatus(err)
    }
  } else {
    if (getConnectionId().length === 11) {
      setStatus('Ready')
    } else {
      setStatus('Enter device ID')
    }
  }
}

async function tryConnection() {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject('Connection timed out. Make sure the device id is correct and try again.')
    }, 5000)

    const peer = new peerjs.Peer()
    const id = getConnectionId() || ''
    const connectionId = `flownio-airdash-${id}`
    const conn = peer.connect(connectionId)
    conn.on('open', async function() {
      clearTimeout(timeout)
      peer.destroy()
      resolve('success')
    })
    conn.on('error', function(err) {
      console.log('err', err)
      reject(err)
    })
  })
}

async function sendFile(file, filename) {
  return new Promise((resolve, reject) => {
    setStatus('Connecting...')
    const timeout = setTimeout(() => {
      reject('Connection timed out. Make sure the device id is correct and try again.')
    }, 5000)

    const peer = new peerjs.Peer()
    const id = getConnectionId() || ''
    const connectionId = `flownio-airdash-${id}`
    const conn = peer.connect(connectionId, { metadata: { filename } })
    conn.on('open', async function() {
      clearTimeout(timeout)
      setStatus('Sending...')
      conn.send(file)
    })
    conn.on('data', async function(data) {
      if (data === 'done') {
        await localforage.clear()
        setStatus('Sent ' + filename)
        resolve('done')
      } else {
        console.log('unknown message', data)
        setStatus('Unknown message ' + data)
        reject(data)
      }
    })
    conn.on('error', function(err) {
      console.log('err', err)
      setStatus(err)
      reject(err)
    })
  })
}

function setStatus(status) {
  document.querySelector('#message').textContent = status
}