import { primaryColor } from './consts.js'

export function setStatus(status) {
    document.querySelector('#message').textContent = status
}

export function renderAddDevice(showAddButton) {
    if (showAddButton) {
        return `<button  id="add-device-btn" style="cursor: pointer; background: none; border: none; outline: 0; color: ${primaryColor}; padding: 10px 0;">+ Add Receiving Device</button>`
    } else {
        const codeInputs = `<input id="code-input">`
        return codeInputs + `<p>Enter device code</p>`
    }
}

export function renderDeviceRow(code, device, checked) {
    const statusMessage = device.getStatusMessage()
    const statusColor = device.getStatusColor()

    console.log('render device row', statusMessage, statusColor, device);

    return `
      <div class="device" style="background: none; cursor: pointer;">
          <label class="mdl-radio mdl-js-radio mdl-js-ripple-effect" style="padding-right: 15px;">
              <input class="device-radio" type="radio" id="${code}" name="device" value="${code}" ${checked ? 'checked' : ''}>
          </label>
          <div style="display: inline-block; padding: 10px; vertical-align: middle;">
              <div style="font-size: 18px">${device.name}</div>
              <div style="font-size: 14px; color: #555;">
                  <span class="device-status-indicator" style="border-radius: 10px; width: 10px; height: 10px; background: ${statusColor}; margin-right: 5px; display: inline-block"></span> 
                  <span class="device-status">${statusMessage || 'Unknown error'}</span> -
                  <span class="device-status">${code}</span>
              </div>
          </div>
          <div class="remove-device-btn" style="cursor: pointer; background: none; border: 0; padding: 14px; outline: none; color: #aaa; float: right;" data-device-id="${code}">
              <i class="material-icons">close</i>
          </div>
      </div>
    `
}