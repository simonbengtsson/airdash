import { tryConnection, sendPayload } from './connection.js'
import { parseFormData } from './bodyParser.js'

console.log('Loading app.js')

const primaryColor = '#25AE88'
let showAddButton = true;

; (async function () {
  try {
    await navigator.serviceWorker.register('./sw.js')
    navigator.serviceWorker.addEventListener('message', swMessageReceived);
  } catch (err) {
    console.log('sw failed', err)
  }

  render()
  await connectToDevices()
})()

const deviceStatuses = {}

async function connectToDevices() {
  const devices = getDevices()
  for (const [id, device] of Object.entries(devices)) {
    deviceStatuses[id] = { color: '#f1c40f', message: 'Connecting' }
    render()
    tryConnection(id).then(() => {
      deviceStatuses[id] = { color: primaryColor, message: 'Ready' }
    }).catch(err => {
      console.error(err)
      const message = err.error || 'Could not connect'
      deviceStatuses[id] = { color: '#e74c3c', message: message }
    }).then(() => {
      render()
    })
  }
}

async function swMessageReceived(event) {
  console.log('Message received')
  let { body, headers } = event.data
  const request = new Request('', { method: 'POST', body, headers })

  try {
    const { payload, meta } = await parseFormData(request)
    const activeDevice = getActiveDevice() || ''
    await sendPayload(payload, meta, activeDevice, setStatus)
  } catch (error) {
    console.error(error)
    setStatus(error)
  }
}

function render() {
  let activeDevice = getActiveDevice()
  const devices = getDevices()
  if (!devices[activeDevice]) {
    activeDevice = Object.keys(devices)[0]
  }
  const deviceRows = Object
    .entries(devices)
    .map(([id, obj]) => renderDeviceRow(id, obj, id === activeDevice))
    .join('')
  const content = `
    <section>
        <form>${deviceRows}</form>
        <div style="clear:both;"></div>
        <div style="margin: 10px 0;">${renderAddDevice()}</div>
    </section>
    <section style="margin-bottom: 40px">
        <p id="message" style="min-height: 20px;"></p>
        <form id="file-form" action="./" method="POST" enctype="multipart/form-data">
            <input name="rawtext" type="hidden" value="">
            <label for="file-input" id="file-button">Select file to send</label>
            <!-- bodyParser.js requires that the file input is the last element -->
            <input id="file-input" name="file" type="file" style="opacity: 0; position: absolute; z-index: -1">
        </form>
        <p style="color: #aaa; text-align: center; margin-top: 50px;">v0.2.0</p>
    </section>
  `
  document.querySelector('#content').innerHTML = content
  attachDocument()
}

function renderAddDevice() {
  if (showAddButton) {
    return `<button  id="add-device-btn" style="cursor: pointer; background: none; border: none; outline: 0; color: ${primaryColor}; padding: 10px 0;">+ Add Receiving Device</button>`
  } else {
    const codeInputs = `<input id="code-input">`
    return codeInputs + `<p>Enter device code</p>`
  }
}

function renderDeviceRow(code, device, checked) {
  const status = deviceStatuses[code] || {}
  return `
    <div class="device" style="background: none; cursor: pointer;position:relative">
        <label class="mdl-radio mdl-js-radio mdl-js-ripple-effect" style="padding-right: 15px;">
            <input class="device-radio" type="radio" id="${code}" name="device" value="${code}" ${checked ? 'checked' : ''}>
        </label>
        <div style="display: inline-block; padding: 10px; vertical-align: middle;">
            <div style="font-size: 18px;">${device.name}</div>
            <div style="font-size: 14px; color: #555;">
                <span class="device-status-indicator" style="border-radius: 10px; width: 10px; height: 10px; background: ${status.color || '#e74c3c'}; margin-right: 5px; display: inline-block"></span> 
                <span class="device-status">${status.message || 'Unknown error'}</span> -
                <span class="device-status">${code}</span>
            </div>
        </div>
        <div class="remove-device-btn" 
          style="cursor: pointer; background: none; border: 0; padding: 14px; outline: none; color: #aaa; float: right;" 
          data-device-id="${code}">
            <i class="material-icons">close</i>
        </div>
    </div>
  `
}

function attachDocument() {
  if (!showAddButton) {
    new Cleave('#code-input', {
      delimiter: '-',
      blocks: [3, 3, 3],
      numericOnly: true
    });
  }

  document
    .querySelector('#file-input')
    .addEventListener('change', (e) => {
      const element = e.currentTarget
      // We could send the file directly here, but submitting it with the form
      // makes it easier to debug the service worker used for handling files from
      // the Android share menu
      console.log('File picked', element.files[0].name)
      document.querySelector('#file-form').submit()
      setStatus('Preparing...')
    })

  const codeInputElement = () => document.querySelector('#code-input')
  if (codeInputElement()) {
    codeInputElement()
      .addEventListener('focusout', (e) => {
        if (!e.currentTarget.disabled) {
          showAddButton = true
          render()
        }
      })

    codeInputElement()
      .addEventListener('input', async (e) => {
        const element = e.currentTarget
        if (element.value.length === 11) {
          await tryAddingDevice(element.value, element)
        }
      })
  }

  const addDeviceButton = document.querySelector('#add-device-btn')
  if (addDeviceButton) {
    addDeviceButton
      .addEventListener('click', () => {
        showAddButton = false
        render()
        codeInputElement().focus()
      })
  }

  document
    .querySelectorAll('.remove-device-btn')
    .forEach((btn) => {
      btn.addEventListener('click', (e) => {
        console.log('clicked', e.currentTarget.dataset)
        let devices = getDevices()
        const deviceId = e.currentTarget.dataset.deviceId
        delete devices[deviceId]
        localStorage.setItem('devices', JSON.stringify(devices))
        render();
        e.stopPropagation()
      })
    })

  document.querySelectorAll('.device')
    .forEach((btn) => {
      btn.addEventListener('click', (e) => {
        const element = e.currentTarget
        element.querySelector('input').checked = true
        setActiveDevice(element.value)
      })
    })

  let deferredPrompt;
  document.querySelector('#android-install')
    .addEventListener('click', () => {
      deferredPrompt.prompt()
    })
  window
    .addEventListener('beforeinstallprompt', (e) => {
      deferredPrompt = e
    });
}

async function tryAddingDevice(code, element) {
  console.log(code)
  element.disabled = true
  setStatus('Connecting...')
  try {
    const result = await tryConnection(code)
    addDevice(code, result.deviceName || code)
    deviceStatuses[code] = { color: primaryColor, message: 'Ready' }
    setActiveDevice(code)
    showAddButton = true
    render()
  } catch (error) {
    setStatus(error)
    element.disabled = false
    element.focus()
  }
}

function getDevices() {
  return JSON.parse(localStorage.getItem('devices') || '{}')
}

function addDevice(code, name) {
  const newDevice = { name, addedAt: new Date() }
  const devices = getDevices()
  devices[code] = newDevice
  localStorage.setItem('devices', JSON.stringify(devices))
}

function setActiveDevice(code) {
  localStorage.setItem('connection-id', code)
}

function getActiveDevice() {
  return localStorage.getItem('connection-id') || ''
}

function setStatus(status) {
  document.querySelector('#message').textContent = status
}