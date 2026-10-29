// Собирает автономный файл, чтобы подборку можно было открыть без сервера.
const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const project = path.resolve(root, '../../..');
const templatePath = path.join(root, 'gallery-template.html');
const template = fs.readFileSync(templatePath, 'utf8');
const manifestPath = path.join(root, 'variants.json');

if (!fs.existsSync(manifestPath)) {
  throw new Error(`Не найден манифест концептов: ${manifestPath}`);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const variants = Array.isArray(manifest) ? manifest : manifest.variants;
if (!Array.isArray(variants) || variants.length !== 20) {
  throw new Error('variants.json должен содержать ровно 20 вариантов в массиве или поле variants.');
}

function embeddedImage(relativePath) {
  const absolutePath = path.resolve(root, relativePath);
  if (!absolutePath.startsWith(root + path.sep)) {
    throw new Error(`Путь изображения выходит за папку галереи: ${relativePath}`);
  }
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`Не найдено изображение: ${absolutePath}`);
  }
  return `data:image/png;base64,${fs.readFileSync(absolutePath).toString('base64')}`;
}

const cards = variants.map((item, index) => {
  const number = String(index + 1).padStart(2, '0');
  const filename = item.file || item.image || `warrior-${number}.png`;
  const label = String(item.name || item.label || `Вариант ${number}`);
  return {
    number,
    label,
    image: embeddedImage(filename),
  };
});

const assetPaths = {
  character: path.join(project, 'assets/art_presets/approved/warrior_format_v1/character.png'),
  dungeon: path.join(project, 'assets/art_presets/trials/dungeon_room_v2/floor.png'),
};
const biomeNames = ['forest', 'ice', 'volcanic', 'desert', 'swamp'];
const demoAssets = {
  character: `data:image/png;base64,${fs.readFileSync(assetPaths.character).toString('base64')}`,
  biomes: { stone: `data:image/png;base64,${fs.readFileSync(assetPaths.dungeon).toString('base64')}` },
};
for (const biome of biomeNames) {
  const file = path.join(project, `assets/art_presets/trials/biomes_v1/${biome}/floor.png`);
  demoAssets.biomes[biome] = `data:image/png;base64,${fs.readFileSync(file).toString('base64')}`;
}

const result = template
  .replace('__VARIANTS_JSON__', JSON.stringify(cards).replace(/</g, '\\u003c'))
  .replace('__DEMO_ASSETS_JSON__', JSON.stringify(demoAssets).replace(/</g, '\\u003c'));
fs.writeFileSync(path.join(root, 'gallery.html'), result, 'utf8');
console.log(`Создана ${path.join(root, 'gallery.html')} (${cards.length} концептов, автономный HTML).`);
