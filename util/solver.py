import numpy as np
from scipy.optimize import minimize


def _objective(deltas, B, f):
    norm_deltas = B * (deltas / np.sum(deltas))
    x_coords = np.cumsum(norm_deltas)

    full_x = np.concatenate(([0], x_coords))
    total_err = 0

    for i in range(len(full_x) - 2):
        x_i, x_j = full_x[i], full_x[i + 1]
        x_seg = np.linspace(x_i, x_j, 100)
        y_f = f(x_seg)
        y_line = np.interp(x_seg, [x_i, x_j], [f(x_i), f(x_j)])
        total_err += np.trapezoid(np.abs(y_f - y_line), x_seg)

    xn = full_x[-2]
    B_v = full_x[-1]
    x_tail = np.linspace(xn, B_v, 100)
    total_err += np.trapezoid(np.abs(f(x_tail) - f(xn)), x_tail)

    return total_err


def solve(f, B: float = 5000, n: int = 3):
    """
    Given a (supposedly continuous) function f:[0,B]->R, find n points that approximate
    the curve, in a source engine nearest-plane fashion.

    Parameters
    ----------
    f -- the function to optimize
    B -- the maximum value to test f (default 5000)
    n -- the number of points to find (default 3)
    """
    deltas = np.ones(n + 1)
    bounds = [(1e-5, None) for _ in range(n + 1)]

    res = minimize(_objective, deltas, args=(B, f), bounds=bounds, method="L-BFGS-B")

    final_d = B * (res.x / np.sum(res.x))
    x_opt = np.cumsum(final_d)[:-1]
    return x_opt


def _plot_results(f, x_opt, B=5000):
    import matplotlib.pyplot as plt

    x_dense = np.linspace(0, B, 1000)
    y_dense = f(x_dense)

    x_poly = np.concatenate(([0], x_opt, [B]))
    y_poly = [f(x) for x in x_opt]
    y_poly = [f(0)] + y_poly + [y_poly[-1]]

    plt.figure(figsize=(14, 7))
    plt.plot(
        x_dense, y_dense, label="Original Curve $f(x)$", color="gray", alpha=0.5, lw=2
    )
    plt.plot(
        x_poly, y_poly, "o-", label="Optimized Polyline", color="blue", markersize=4
    )

    for xi in x_opt:
        plt.axvline(xi, color="red", linestyle="--", alpha=0.2, lw=1)

    plt.title(f"Best Polyline fit of $f(x)$ given a $L^1$ metric (n={len(x_opt)})")
    plt.xlabel("x")
    plt.ylabel("f(x)")
    plt.legend()
    plt.grid(True, which="both", linestyle="--", alpha=0.5)
    plt.show()


if __name__ == "__main__":

    def f(x):
        return np.where(x == 0, 1, 1 / np.sqrt(x))

    results = solve(f, n=3)
    _plot_results(f, results)
