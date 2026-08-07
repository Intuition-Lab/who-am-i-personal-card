export class PersonalModelAuthorizationError extends Error {
  constructor(code, message, { status = 403 } = {}) {
    super(message);
    this.name = "PersonalModelAuthorizationError";
    this.code = code;
    this.status = status;
  }

  toJSON() {
    return {
      code: this.code,
      message: this.message,
    };
  }
}

export function authorizationError(code, message, options) {
  return new PersonalModelAuthorizationError(code, message, options);
}
