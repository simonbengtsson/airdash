
import { primaryColor, errorColor, warnColor } from './consts.js'

export const STATUS_CONNECTING = { message: 'Connecting', color: warnColor }
export const STATUS_ERROR = { message: 'Could not connect', color: errorColor }
export const STATUS_READY = { message: 'Ready', color: primaryColor }

export const STATUSES = {
    connecting: STATUS_CONNECTING,
    ready: STATUS_READY,
    error: STATUS_ERROR,
}