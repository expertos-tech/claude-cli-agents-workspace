<!-- source: maintainers/README.md sha256:6adb36b25fb324bdefcba1477d4367deb646336ff6a902d1788d645c33ef56cc -->

# maintainers

[English](../../../maintainers/README.md) · [Português (Brasil)](../../pt-BR/maintainers/README.md) · Español

El trabajo de quien mantiene el producto, a la vista. Nada de esto se copia jamás a un workspace instalado, y nada de
esto nombra una empresa, un cliente ni una persona: la evidencia privada del uso real se queda en `tmp/`, ignorado por
git. El proceso que escribe estos archivos está en el `CLAUDE.md` de la raíz y en `.claude/rules/process.md`.

| Carpeta | Qué guarda |
| --- | --- |
| `backlog/` | Ideas, defectos, mejoras y deudas del producto que aún no se convirtieron en un pedido; un ítem por archivo |
| `plans/` | Diseños: el problema, las opciones, una recomendación y las decisiones numeradas para el owner |
| `requests/` | Pedidos funcionales listos para ejecutar con `/caw-prompt`: objetivo, BR-n, AC-n, fuera de alcance, etapas con effort |
| `reviews/` | Informes de revisiones independientes (por ejemplo una revisión final antes de un release); los crea la primera |
