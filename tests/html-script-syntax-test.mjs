import fs from 'node:fs'

for (const file of [
  'web/index.html',
  'web/merchant.html',
]) {
  const html = fs.readFileSync(file, 'utf8')
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  scripts.forEach((match, index) => {
    if (match[0].includes(' src=')) return
    try { new Function(match[1]) }
    catch (error) { throw new Error(`${file} inline script ${index + 1}: ${error.message}`) }
  })
}

console.log('HTML inline script syntax: passed')
