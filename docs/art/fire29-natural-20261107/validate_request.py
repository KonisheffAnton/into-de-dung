"""Validate nested image-size constraints against the freshly fetched API schema."""
import json
from pathlib import Path
import sys
import uuid

request_path, schema_path, endpoint = sys.argv[1:]
schema = json.loads(Path(schema_path).read_bytes())
reference = schema['paths']['/' + endpoint]['post']['requestBody']['content']['application/json']['schema']['$ref']
def validate(value, contract, location='request'):
    """Only the scalar/object/array subset used by the pinned PixelLab requests."""
    if '$ref' in contract:
        target = schema
        for part in contract['$ref'].removeprefix('#/').split('/'):
            target = target[part.replace('~1', '/').replace('~0', '~')]
        return validate(value, target, location)
    if 'anyOf' in contract:
        branches = [validate(value, option, location) for option in contract['anyOf']]
        return [] if any(not branch for branch in branches) else [location + ': anyOf']
    supported = {'type', 'properties', 'required', 'additionalProperties', 'items',
                 'minimum', 'maximum', 'minLength', 'maxLength', 'minItems', 'maxItems',
                 'enum', 'title', 'description', 'default', 'example', 'deprecated', 'format'}
    unknown = set(contract) - supported
    if unknown:
        return [location + ': unsupported schema keyword ' + ','.join(sorted(unknown))]
    types = {'object': lambda v: isinstance(v, dict), 'array': lambda v: isinstance(v, list),
             'string': lambda v: isinstance(v, str), 'boolean': lambda v: isinstance(v, bool),
             'integer': lambda v: isinstance(v, int) and not isinstance(v, bool),
             'number': lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
             'null': lambda v: v is None}
    kind = contract.get('type')
    if kind and (kind not in types or not types[kind](value)):
        return [location + ': type']
    errors = []
    if 'format' in contract:
        if contract['format'] == 'uuid':
            try:
                uuid.UUID(value)
            except (ValueError, TypeError, AttributeError):
                errors.append(location + ': uuid')
        else:
            errors.append(location + ': unsupported format ' + contract['format'])
    if 'enum' in contract and value not in contract['enum']:
        errors.append(location + ': enum')
    for bound in ('minimum', 'maximum', 'minLength', 'maxLength', 'minItems', 'maxItems'):
        if bound not in contract:
            continue
        actual = len(value) if bound.endswith(('Length', 'Items')) else value
        if (bound.startswith('min') and actual < contract[bound]) or (bound.startswith('max') and actual > contract[bound]):
            errors.append(location + ': ' + bound)
    if isinstance(value, dict):
        properties = contract.get('properties', {})
        for name in contract.get('required', []):
            if name not in value:
                errors.append(location + '/' + name + ': required')
        for name, child in value.items():
            if name in properties:
                errors += validate(child, properties[name], location + '/' + name)
            elif contract.get('additionalProperties') is False:
                errors.append(location + '/' + name + ': unexpected')
    if isinstance(value, list) and 'items' in contract:
        for index, child in enumerate(value):
            errors += validate(child, contract['items'], location + '/' + str(index))
    return errors

request = json.loads(Path(request_path).read_bytes())
errors = validate(request, {'$ref': reference})
if errors:
    # Never print payloads: images are large and validation only needs the location.
    for error in errors:
        print('INVALID:', error)
    raise SystemExit(1)
print('PASS API request schema:', endpoint)
