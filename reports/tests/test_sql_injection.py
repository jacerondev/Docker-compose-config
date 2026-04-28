# filepath: reports/tests/test_sql_injection.py

def test_no_string_interpolation_in_queries(tmp_path):
    """Verifica que no haya concatenación de strings en queries SQL."""
    import ast
    import pathlib
    SRC_DIR = pathlib.Path(__file__).parent.parent / 'src'

    violations = []
    for pyfile in SRC_DIR.rglob('*.py'):
        tree = ast.parse(pyfile.read_text())
        for node in ast.walk(tree):
            # Detectar execute() con JoinedStr (f-string) como argumento
            if (isinstance(node, ast.Call) and
                isinstance(node.func, ast.Attribute) and
                node.func.attr == 'execute' and
                node.args and isinstance(node.args[0], ast.JoinedStr)):
                violations.append(f"{pyfile}:{node.lineno}")

    assert not violations, f"SQL injection potencial en: {violations}"