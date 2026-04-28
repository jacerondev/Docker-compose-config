## Reglas de acceso a base de datos en reports-api

### PROHIBIDO
- ❌ `cursor.execute(f"SELECT ... WHERE id = {user_input}")`
- ❌ `cursor.execute("SELECT ... WHERE id = " + str(user_input))`
- ❌ `text(f"SELECT ... {variable}")` en SQLAlchemy

### OBLIGATORIO
- ✅ `cursor.execute("SELECT ... WHERE id = %s", (user_id,))` — psycopg2 parametrizado
- ✅ `session.query(Model).filter(Model.id == user_id)` — SQLAlchemy ORM
- ✅ `text("SELECT ... WHERE id = :id").bindparams(id=user_id)` — SQLAlchemy textual

El usuario `db_read_only_user` solo tiene permisos SELECT — esto limita el daño
posible ante una inyección exitosa, pero NO elimina el riesgo de exfiltración de datos.