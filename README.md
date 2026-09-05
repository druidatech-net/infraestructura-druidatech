# Infraestructura DruidaTech — laboratorio propio y producción en la nube

La infraestructura sobre la que corren los proyectos web de DruidaTech: un
laboratorio en hardware propio para desarrollar y probar, y un servidor pequeño
alquilado en la nube para producción. Toda la infraestructura, del laboratorio a
la nube, la diseñó, la montó y la opera **Edgardo Rodríguez**.

**Un proyecto que corre sobre esto:**
[artedehoy-web](https://github.com/druidatech-net/artedehoy-web), sitio y
plataforma de cursos en video.

---

## La idea en una frase

Se desarrolla y se prueba en casa. Se publica en la nube. Y las webs nunca
dependen de la casa: si el laboratorio se apaga, los sitios y sus datos siguen.
La única pieza que vive en casa por decisión propia es el correo.

---

## Cómo está armado

```mermaid
flowchart LR
    subgraph LAB[Laboratorio · hardware propio]
        direction TB
        H[Host KVM<br/>escritorio + máquinas virtuales]
        H --> W[VM web de pruebas<br/>réplica de producción]
        H --> C[VM correo]
        H --> B[(VM respaldo<br/>disco dedicado)]
        H --> U[VM controlador WiFi]
        H --> K[MikroTik virtual<br/>para ensayar la red]
        M[Módem del proveedor] --> R[Router MikroTik] --> H
    end
    subgraph NUBE[Nube · producción]
        direction TB
        V[VPS<br/>nginx + aplicaciones Flask<br/>servicios systemd]
        S[(Reservorio de medios<br/>un depósito privado por proyecto)]
        D[DNS por API]
    end
    W -->|"deploy por SSH<br/>cuando la prueba pasó"| V
```

---

## El laboratorio

**Un solo equipo, cuatro roles.** Una PC de escritorio con ocho núcleos y treinta
y dos gigabytes de memoria, con Ubuntu. Es a la vez el escritorio de trabajo,
el host de máquinas virtuales con KVM, el servidor de archivos de la red local
y el puesto de desarrollo.

**Cinco máquinas virtuales**, que arrancan solas con el equipo:

| Máquina | Para qué |
|---|---|
| Web de pruebas | Réplica del entorno de producción: mismo nginx, mismas aplicaciones, mismos servicios. Lo que funciona acá, sube. |
| Correo | Servidor de correo completo y propio para todos los dominios de la empresa: buzones, webmail y autenticación del dominio (SPF, DKIM y DMARC), sin depender de un proveedor. |
| Respaldo | Recibe las copias de la nube en un disco dedicado. |
| Controlador WiFi | Administra los puntos de acceso de la red. |
| MikroTik virtual | Un router de laboratorio para ensayar configuraciones de red antes de tocar el router real. |

**La red.** El módem del proveedor delante, en doble NAT, y detrás un router
MikroTik que gobierna la red interna. Las máquinas virtuales reciben su
dirección por DHCP con reserva en el router; ninguna lleva dirección fija
adentro. Es una regla de la casa: la red se administra desde un solo lugar.

**Un disco que el host no ve.** El disco de respaldo pertenece a una sola
máquina virtual. Si el host lo montara mientras la VM lo usa, el sistema de
archivos se corrompe. Una regla de udev lo esconde del automontaje del
escritorio, identificándolo por su número de serie y no por su letra, que
cambia. Está en [`codigo/99-disco-solo-vm.rules`](codigo/99-disco-solo-vm.rules).

---

## Cómo se prueba antes de subir

```mermaid
flowchart LR
    A[Cambio] --> B[VM web de pruebas]
    B --> C{¿Funciona igual<br/>que en producción?}
    C -->|no| A
    C -->|sí| D[Deploy por SSH al VPS]
    D --> E[Verificación en vivo<br/>capturas automáticas]
```

La VM de pruebas corre el mismo nginx, las mismas aplicaciones y los mismos
servicios que el servidor de producción. Un cambio se prueba ahí, se verifica
con capturas automáticas del navegador, y recién después se copia al servidor
por SSH. Si algo se rompe, se rompe en casa.

El mismo camino se usó para piezas más grandes. La conversión de video a
streaming adaptativo, por ejemplo, nació y se ajustó en el laboratorio; cuando
funcionó, se mudó al VPS con las mismas reglas.

---

## La nube

**Un servidor chico.** Una máquina virtual de dos gigabytes de memoria en
Santiago de Chile, por menos de doce dólares al mes. Aloja varios sitios y sus
aplicaciones, cada una como servicio de systemd detrás de nginx. HTTPS con
certificados que se renuevan solos. Un freno automático a los intentos de
entrada repetidos. Un watchdog que reinicia lo que se cuelga.

**Almacenamiento de objetos.** Un depósito privado por proyecto, compatible con
S3. Videos, imágenes y documentos viven ahí, no en el servidor, y se entregan
por enlaces firmados que vencen.

**DNS por API.** Los dominios se administran por comando, no por panel, y cada
cambio se verifica con una consulta antes de darlo por hecho.

**Vigías.** Guiones pequeños, disparados por temporizadores de systemd, que
revisan que las tareas de fondo avancen y se arreglan solos si algo quedó a
mitad. El de la conversión de video está en
[`codigo/vigia-cocina.sh`](codigo/vigia-cocina.sh): hace una sola pregunta por
video, "¿ya está convertido?", y si no, lo convierte. Si la vuelta anterior
falló, la siguiente lo agarra igual.

---

## El reservorio de videos

Las clases en video son el producto de una academia, y son pesadas. No viven en
el servidor: viven en el reservorio, un depósito privado de almacenamiento de
objetos, uno por proyecto.

- **Nada se sirve por dirección fija.** La aplicación decide quién puede ver qué
  y entrega enlaces firmados que vencen. El video viaja del reservorio al
  reproductor sin pasar por el servidor web.
- **Cada video se convierte solo.** Un vigía revisa el reservorio, encuentra los
  videos sin convertir y los deja en tres calidades, en fragmentos, para
  streaming adaptativo. El original nunca se toca.
- **Todo tiene copia.** El reservorio se replica cada cinco minutos en el
  laboratorio, en la máquina de respaldo.

Cómo se protege ese contenido, con el código de la entrega firmada, está contado
en [artedehoy-web](https://github.com/druidatech-net/artedehoy-web#el-reservorio-de-videos-y-c%C3%B3mo-se-cuida).

---

## Correo propio, en infraestructura propia

El correo de todos los dominios de la empresa corre en un servidor propio, en el
laboratorio: buzones, webmail y la autenticación del dominio que hace que los
mensajes lleguen y no caigan en spam. Es la única pieza de producción que sigue
en casa, por decisión propia, y la que más cuidado de red exige: es el servicio
que primero prueba cualquier atacante.

---

## Las webs nunca dependen de la casa

Todo empezó en casa: las webs se servían desde el laboratorio, con dirección
dinámica y puertos abiertos en doble NAT. Funcionaba, pero cualquier corte de
luz o de internet apagaba los sitios.

En agosto de 2026 la producción se mudó a la nube, por fases y sin cortes:
primero los archivos al almacenamiento de objetos, después la conversión de
video, después los sitios y sus aplicaciones. Cada fase con una prueba de fuego
al final: apagar las máquinas de casa y verificar, desde un teléfono con datos
móviles, que todo seguía andando.

El laboratorio quedó con tres roles: desarrollar y probar, guardar las copias,
y el correo.

---

## Respaldos

```mermaid
flowchart LR
    S[(Almacenamiento de objetos<br/>videos y materiales)] -->|"réplica cada 5 min"| B[(VM de respaldo<br/>disco dedicado, en el laboratorio)]
    V[VPS<br/>bases de datos] -->|"copia cada noche<br/>30 días de historia"| B
    G[Repositorios privados<br/>en GitHub] -.->|"código"| B
```

| Qué | Dónde vive | Copia |
|---|---|---|
| Código | Servidor | Repositorios privados en GitHub |
| Bases de datos | Servidor | Cada noche a la VM de respaldo, con treinta días de historia. Restauración probada. |
| Videos y materiales | Almacenamiento de objetos | Réplica cada cinco minutos a la VM de respaldo |

La copia sale de la nube y entra al laboratorio, nunca al revés. Si la nube
desaparece, todo está en casa. Si la casa desaparece, producción no se entera.

---

## Lo que sigue

El host está migrando a **Proxmox**. Antes de tocar el disco real, la migración
se ensayó completa dentro de una máquina virtual, con un clon del sistema. El
ensayo encontró cuatro problemas que en el corte real hubieran costado una
noche: un cargador de arranque mal apuntado, un kernel roto heredado, una
referencia a un disco que ya no existía y un servicio que no arrancaba solo. Se
corrigieron en el ensayo. El corte real se hace con esos cuatro ya resueltos.

---

## Con qué está hecho

| Capa | Herramienta |
|---|---|
| Virtualización | KVM con libvirt; migración a Proxmox en curso |
| Red | MikroTik RouterOS, físico y virtual |
| Servidor web | nginx, HTTPS con Let's Encrypt |
| Aplicaciones | Python con Flask, gunicorn, servicios systemd |
| Medios | Almacenamiento de objetos compatible con S3 |
| Video | ffmpeg, streaming adaptativo HLS |
| Vigilancia | Temporizadores de systemd, watchdog, fail2ban |
| Verificación | Capturas automáticas del navegador antes y después de cada cambio |
| Respaldo | Réplica de objetos y copia diaria de bases a un disco dedicado |

---

## Qué se muestra acá y qué no

Este repositorio cuenta el diseño. Contiene los diagramas, la explicación y dos
piezas de código reales:

| Archivo | Qué es |
|---|---|
| [`codigo/vigia-cocina.sh`](codigo/vigia-cocina.sh) | El vigía que revisa y convierte los videos pendientes |
| [`codigo/99-disco-solo-vm.rules`](codigo/99-disco-solo-vm.rules) | La regla que esconde el disco de respaldo al host |

No contiene direcciones de red, nombres de máquinas, números de serie,
credenciales ni rutas internas. Es un caso de estudio, no un mapa.

---

## Derechos

El código está bajo [licencia MIT](LICENSE). Ver [DERECHOS.md](DERECHOS.md).

Código © 2026 DruidaTech (Edgardo Rodríguez)

Diseñado y operado por **Edgardo Rodríguez** · [DruidaTech](https://druidatech.net)
