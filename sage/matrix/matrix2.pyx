"""
Base class for matrices, part 2

TESTS:
    sage: m = matrix(ZZ['x'], 2, 3, [1..6])
    sage: loads(dumps(m)) == m
    True
"""

# For design documentation see matrix/docs.py.

################################################################################
#       Copyright (C) 2005, 2006 William Stein <wstein@gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL).
#  The full text of the GPL is available at:
#
#                  http://www.gnu.org/licenses/
################################################################################

include "../ext/stdsage.pxi"
include "../ext/python.pxi"

from sage.misc.randstate cimport randstate, current_randstate
from sage.structure.sequence import Sequence
from sage.combinat.combinat import combinations_iterator
from sage.structure.element import is_Vector
from sage.misc.misc import verbose, get_verbose, graphics_filename
from sage.rings.number_field.all import is_NumberField
from sage.rings.integer_ring import ZZ
from sage.rings.integer import Integer
from sage.rings.rational_field import QQ

import sage.modules.free_module
import matrix_space
import berlekamp_massey
from sage.modules.free_module_element import is_FreeModuleElement

cdef class Matrix(matrix1.Matrix):
    def _backslash_(self, B):
        """
        Used to compute $A \\ B$, i.e., the backslash solver operator.

        EXAMPLES:
            sage: A = matrix(QQ, 3, [1,2,4,2,3,1,0,1,2])
            sage: B = matrix(QQ, 3, 2, [1,7,5, 2,1,3])
            sage: C = A._backslash_(B); C
            [  -1    1]
            [13/5 -3/5]
            [-4/5  9/5]
            sage: A*C == B
            True
            sage: A._backslash_(B) == A \ B
            True
            sage: A._backslash_(B) == A.solve_right(B)
            True        
        """
        return self.solve_right(B)

    def subs(self, in_dict=None, **kwds):
        """
        EXAMPLES:
            sage: var('a,b,d,e')
            (a, b, d, e)
            sage: m = matrix([[a,b], [d,e]])
            sage: m.substitute(a=1)
            [1 b]
            [d e]
            sage: m.subs(a=b, b=d)
            [b d]
            [d e]
        """
        v = [a.subs(in_dict, **kwds) for a in self.list()]
        return self.new_matrix(self.nrows(), self.ncols(), v)

    def solve_left(self, B, check=True):
        """
        If self is a matrix $A$, then this function returns a vector
        or matrix $X$ such that $X A = B$.  If $B$ is a vector then
        $X$ is a vector and if $B$ is a matrix, then $X$ is a matrix.

        INPUT:
            B -- a matrix
            check -- bool (default: True) -- if False and self is nonsquare,
                     may not raise an error message even if there is no solution.
                     This is faster but more dangerous.

        EXAMPLES:
            sage: A = matrix(QQ,4,2, [0, -1, 1, 0, -2, 2, 1, 0])
            sage: B = matrix(QQ,2,2, [1, 0, 1, -1])
            sage: X = A.solve_left(B)
            sage: X*A == B
            True
        """
        return self.transpose().solve_right(B.transpose(), check=check).transpose()
    
    def solve_right(self, B, check=True):
        r"""
        If self is a matrix $A$, then this function returns a vector
        or matrix $X$ such that $A X = B$.  If $B$ is a vector then
        $X$ is a vector and if $B$ is a matrix, then $X$ is a matrix.

        NOTE: In SAGE one can also write \code{A \ B} for
        \code{A.solve_right(B)}, i.e., SAGE implements the ``the
        MATLAB/Octave backslash operator''.

        INPUT:
            B -- a matrix or vector
            check -- bool (default: True) -- if False and self is nonsquare,
                     may not raise an error message even if there is no solution.
                     This is faster but more dangerous.  

        OUTPUT:
            a matrix or vector

        SEE ALSO: solve_left

        EXAMPLES:
            sage: A = matrix(QQ, 3, [1,2,3,-1,2,5,2,3,1])
            sage: b = vector(QQ,[1,2,3])
            sage: x = A \ b; x
            (-13/12, 23/12, -7/12)
            sage: A * x
            (1, 2, 3)

        We solve with A nonsquare:
            sage: A = matrix(QQ,2,4, [0, -1, 1, 0, -2, 2, 1, 0]); B = matrix(QQ,2,2, [1, 0, 1, -1])
            sage: X = A.solve_right(B); X
            [-3/2  1/2]
            [  -1    0]
            [   0    0]
            [   0    0]
            sage: A*X == B
            True

        Another nonsingular example:
            sage: A = matrix(QQ,2,3, [1,2,3,2,4,6]); v = vector([-1/2,-1])
            sage: x = A \ v; x
            (-1/2, 0, 0)
            sage: A*x == v
            True

        Same example but over $\ZZ$:
            sage: A = matrix(ZZ,2,3, [1,2,3,2,4,6]); v = vector([-1,-2])
            sage: A \ v
            (-1, 0, 0)

        An example in which there is no solution:
            sage: A = matrix(QQ,2,3, [1,2,3,2,4,6]); v = vector([1,1])
            sage: A \ v
            Traceback (most recent call last):
            ...
            ValueError: matrix equation has no solutions

        A ValueError is raised if the input is invalid:
            sage: A = matrix(QQ,4,2, [0, -1, 1, 0, -2, 2, 1, 0])
            sage: B = matrix(QQ,2,2, [1, 0, 1, -1])
            sage: X = A.solve_right(B)
            Traceback (most recent call last):
            ...
            ValueError: number of rows of self must equal number of rows of B
            
        
        We solve with A singular:
            sage: A = matrix(QQ,2,3, [1,2,3,2,4,6]); B = matrix(QQ,2,2, [6, -6, 12, -12])
            sage: X = A.solve_right(B); X
            [ 6 -6]
            [ 0  0]
            [ 0  0]
            sage: A*X == B
            True

        We illustrate left associativity, etc., of the backslash operator. 
            sage: A = matrix(QQ, 2, [1,2,3,4])
            sage: A \ A
            [1 0]
            [0 1]
            sage: A \ A \ A
            [1 2]
            [3 4]
            sage: A.parent()(1) \ A
            [1 2]
            [3 4]
            sage: A \ (A \ A)
            [  -2    1]
            [ 3/2 -1/2]
            sage: X = A \ (A - 2); X
            [ 5 -2]
            [-3  2]
            sage: A * X
            [-1  2]
            [ 3  2]

        Solving over a polynomial ring:
            sage: x = polygen(QQ, 'x')
            sage: A = matrix(2, [x,2*x,-5*x^2+1,3])
            sage: v = vector([3,4*x - 2])
            sage: X = A \ v
            sage: X
            ((-8*x^2 + 4*x + 9)/(10*x^3 + x), (19*x^2 - 2*x - 3)/(10*x^3 + x))
            sage: A * X == v
            True

        Solving a system over the p-adics:
            sage: k = Qp(5,4)
            sage: a = matrix(k, 3, [1,7,3,2,5,4,1,1,2]); a
            [    1 + O(5^4) 2 + 5 + O(5^4)     3 + O(5^4)]
            [    2 + O(5^4)     5 + O(5^5)     4 + O(5^4)]
            [    1 + O(5^4)     1 + O(5^4)     2 + O(5^4)]
            sage: v = vector(k, 3, [1,2,3])
            sage: x = a \ v; x
            (4 + 5 + 5^2 + 3*5^3 + O(5^4), 2 + 5 + 3*5^2 + 5^3 + O(5^4), 1 + 5 + O(5^4))
            sage: a * x == v
            True        
        """

        if is_Vector(B):
            if self.nrows() != B.degree():
                raise ValueError, "number of rows of self must equal degree of B"
        else:
            if self.nrows() != B.nrows():
                raise ValueError, "number of rows of self must equal number of rows of B"
        
        K = self.base_ring()
        if not K.is_integral_domain():
            raise TypeError, "base ring must be an integral domain"
        if not K.is_field():
            K = K.fraction_field()
            self = self.change_ring(K)

        matrix = True
        if is_Vector(B):
            matrix = False
            C = self.matrix_space(self.nrows(), 1)(B.list())
        else:
            C = B

        if not self.is_square():
            X = self._solve_right_general(C, check=check)
            if not matrix:
                # Convert back to a vector
                return (X.base_ring() ** X.nrows())(X.list())
            else:
                return X
            
        if self.rank() != self.nrows():
            X = self._solve_right_general(C, check=check)
        else:
            X = self._solve_right_nonsingular_square(C, check_rank=False)

        if not matrix:
            # Convert back to a vector
            return X.column(0)
        else:
            return X

    def _solve_right_nonsingular_square(self, B, check_rank=True):
        r"""
        If self is a matrix $A$ of full rank, then this function
        returns a matrix $X$ such that $A X = B$.

        SEE ALSO: \code{self.solve_right} and \code{self.solve_left}

        INPUT:
            B -- a matrix
            check_rank -- bool (default: True)

        OUTPUT:
            matrix

        EXAMPLES:
            sage: A = matrix(QQ,3,[1,2,4,5,3,1,1,2,-1])
            sage: B = matrix(QQ,3,2,[1,5,1,2,1,5])
            sage: A._solve_right_nonsingular_square(B)
            [ -1/7 -11/7]
            [  4/7  23/7]
            [    0     0]
            sage: A._solve_right_nonsingular_square(B, check_rank=False)
            [ -1/7 -11/7]
            [  4/7  23/7]
            [    0     0]
            sage: X = A._solve_right_nonsingular_square(B, check_rank=False)
            sage: A*X == B
            True
        """
        D = self.augment(B).echelon_form()
        return D.matrix_from_columns(range(self.ncols(),D.ncols()))
            

    def pivot_rows(self):
        """
        Return the pivot row positions for this matrix, which are a
        topmost subset of the rows that span the row space and are
        linearly independent.

        OUTPUT:
            list -- a list of integers

        EXAMPLES:
            sage: A = matrix(QQ,3,3, [0,0,0,1,2,3,2,4,6]); A
            [0 0 0]
            [1 2 3]
            [2 4 6]
            sage: A.pivot_rows()
            [1]
        """
        v = self.fetch('pivot_rows')
        if v is not None:
            return list(v)
        v = self.transpose().pivots()
        self.cache('pivot_rows', v)
        return v
        
    def _solve_right_general(self, B, check=True):
        r"""
        This is used internally by the \code{solve_right} command to
        solve for self*X = B when self is not square or not of full
        rank.  It does some linear algebra, then solves a full-rank
        square system.

        INPUT:
            B -- a matrix
            check -- bool (default: True); if False, if there is no
                     solution this function will not detect that fact.

        OUTPUT:
            matrix

        EXAMPLES:
            sage: A = matrix(QQ,2,3, [1,2,3,2,4,6]); B = matrix(QQ,2,2, [6, -6, 12, -12])
            sage: A._solve_right_general(B)
            [ 6 -6]
            [ 0  0]
            [ 0  0]
        """
        pivot_cols = self.pivots()
        A = self.matrix_from_columns(pivot_cols)
        pivot_rows = A.pivot_rows()
        A = A.matrix_from_rows(pivot_rows)
        X = A.solve_right(B.matrix_from_rows(pivot_rows), check=False)
        if len(pivot_cols) < self.ncols():
            # Now we have to put in zeros for the non-pivot ROWS, i.e.,
            # make a matrix from X with the ROWS of X interspersed with
            # 0 ROWS.
            Y = X.new_matrix(self.ncols(), X.ncols())
            # Put the columns of X into the matrix Y at the pivot_cols positions
            for i, c in enumerate(pivot_cols):
                Y.set_row(c, X.row(i))
            X = Y
        if check:
            # Have to check that we actually solved the equation.
            if self*X != B:
                raise ValueError, "matrix equation has no solutions"
        return X
    
    def prod_of_row_sums(self, cols):
        r"""
        Calculate the product of all row sums of a submatrix of $A$ for a
        list of selected columns \code{cols}.

        EXAMPLES:
            sage: a = matrix(QQ, 2,2, [1,2,3,2]); a
            [1 2]
            [3 2]
            sage: a.prod_of_row_sums([0,1])
            15

        Another example:
            sage: a = matrix(QQ, 2,3, [1,2,3,2,5,6]); a
            [1 2 3]
            [2 5 6]
            sage: a.prod_of_row_sums([1,2])
            55
            
        AUTHOR:
            -- Jaap Spies (2006-02-18)
        """
        cdef Py_ssize_t c, row
        pr = 1
        for row from 0 <= row < self._nrows:
            tmp = []
            for c in cols:
#               if c<0 or c >= self._ncols:
#                   raise IndexError, "matrix column index out of range"
                tmp.append(self.get_unsafe(row, c))
            pr = pr * sum(tmp)
        return pr

    def permanent(self):
        r"""
        Calculate and return the permanent of this $m \times n$ matrix using
        Ryser's algorithm.

        Let $A = (a_{i,j})$ be an $m \times n$ matrix over any
        commutative ring, with $m \le n$.   The permanent of $A$ is
        \[
        \text{per}(A) = \sum_\pi a_{1,\pi(1)}a_{2,\pi(2)} \cdots a_{m\,pi(m)}
        \]
        where the summation extends over all one-to-one functions $\pi$ from
        $\{1, \ldots, m\}$ to $\{1, \ldots, n\}$.

        The product $ a_{1,\pi(1)}a_{2,\pi(2)} \cdots a_{m,\pi(m)}$ is called
        diagonal product. So the permanent of an $m \times n$ matrix $A$ is the
        sum of all the diagonal products of $A$.

        Modification of theorem 7.1.1. from Brualdi and Ryser:
        Combinatorial Matrix Theory.
        Instead of deleting columns from $A$, we choose columns from $A$ and
        calculate the product of the row sums of the selected submatrix.

        INPUT:
            A -- matrix of size m x n with m <= n 

        OUTPUT:
            permanent of matrix A

        EXAMPLES:
            sage: M = MatrixSpace(ZZ,4,4)
            sage: A = M([1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1])
            sage: A.permanent()
            24

            sage: M = MatrixSpace(QQ,3,6)
            sage: A = M([1,1,1,1,0,0,0,1,1,1,1,0,0,0,1,1,1,1])
            sage: A.permanent()
            36

            sage: M = MatrixSpace(RR,3,6)
            sage: A = M([1.0,1.0,1.0,1.0,0,0,0,1.0,1.0,1.0,1.0,0,0,0,1.0,1.0,1.0,1.0])
            sage: A.permanent()
            36.0000000000000

        See Sloane's sequence OEIS A079908(3) = 36, "The Dancing School Problems"

            sage: print sloane_sequence(79908)                # optional (internet connection)
            Searching Sloane's online database...
            [79908, 'Solution to the Dancing School Problem with 3 girls and n+3 boys: f(3,n).', [1, 4, 14, 36, 76, 140, 234, 364, 536, 756, 1030, 1364, 1764, 2236, 2786, 3420, 4144, 4964, 5886, 6916, 8060, 9324, 10714, 12236, 13896, 15700, 17654, 19764, 22036, 24476, 27090, 29884, 32864, 36036, 39406, 42980, 46764, 50764, 54986, 59436]]

            sage: M = MatrixSpace(ZZ,4,5)
            sage: A = M([1,1,0,1,1,0,1,1,1,1,1,0,1,0,1,1,1,0,1,0])
            sage: A.permanent()
            32

            See Minc: Permanents, Example 2.1, p. 5.

            sage: M = MatrixSpace(QQ,2,2)
            sage: A = M([1/5,2/7,3/2,4/5])
            sage: A.permanent()
            103/175

            sage: R.<a> = PolynomialRing(ZZ)
            sage: A = MatrixSpace(R,2)([[a,1], [a,a+1]])
            sage: A.permanent()
            a^2 + 2*a

            sage: R.<x,y> = MPolynomialRing(ZZ,2)
            sage: A = MatrixSpace(R,2)([x, y, x^2, y^2])
            sage: A.permanent()
            x^2*y + x*y^2


        AUTHOR:
            -- Jaap Spies (2006-02-16)
                Copyright (C) 2006 Jaap Spies <j.spies@hccnet.nl>
                Copyright (C) 2006 William Stein <wstein@gmail.com>
            -- Jaap Spies (2006-02-21): added definition of permanent

        """
        cdef Py_ssize_t m, n, r
        cdef int sn

        perm = 0
        m = self._nrows
        n = self._ncols
        if not m <= n:
            raise ValueError, "must have m <= n, but m (=%s) and n (=%s)"%(m,n)
        
        for r from 1 <= r < m+1:
            lst = _choose(n, r)
            tmp = []
            for cols in lst:
                tmp.append(self.prod_of_row_sums(cols))
            s = sum(tmp)
            # sn = (-1)^(m-r)
            if (m - r) % 2 == 0:
                sn = 1
            else:
                sn = -1
            perm = perm + sn * _binomial(n-r, m-r) * s
        return perm
    

    def permanental_minor(self, Py_ssize_t k):
        r"""
        Calculates the permanental $k$-minor of a $m \times n$ matrix.

        This is the sum of the permanents of all possible $k$ by $k$
        submatrices of $A$.

        See Brualdi and Ryser: Combinatorial Matrix Theory, p. 203.
        Note the typo $p_0(A) = 0$ in that reference!  For
        applications see Theorem 7.2.1 and Theorem 7.2.4.

        Note that the permanental $m$-minor equals $per(A)$.

        For a (0,1)-matrix $A$ the permanental $k$-minor counts the
        number of different selections of $k$ 1's of $A$ with no two
        of the 1's on the same line.

        INPUT:
            self -- matrix of size m x n with m <= n 

        OUTPUT:
            permanental k-minor of matrix A

        EXAMPLES:
            sage: M = MatrixSpace(ZZ,4,4)
            sage: A = M([1,0,1,0,1,0,1,0,1,0,10,10,1,0,1,1])
            sage: A.permanental_minor(2)
            114

            sage: M = MatrixSpace(ZZ,3,6)
            sage: A = M([1,1,1,1,0,0,0,1,1,1,1,0,0,0,1,1,1,1])
            sage: A.permanental_minor(0)
            1
            sage: A.permanental_minor(1)
            12
            sage: A.permanental_minor(2)
            40
            sage: A.permanental_minor(3)
            36

        Note that if k == m the permanental k-minor equals per(A)

            sage: A.permanent()
            36

            sage: A.permanental_minor(5)
            0

        For C the "complement" of A:

            sage: M = MatrixSpace(ZZ,3,6)
            sage: C = M([0,0,0,0,1,1,1,0,0,0,0,1,1,1,0,0,0,0])
            sage: m, n = 3, 6
            sage: sum([(-1)^k * C.permanental_minor(k)*factorial(n-k)/factorial(n-m) for k in range(m+1)])
            36

            See Theorem 7.2.1 of Brualdi: and Ryser: Combinatorial Matrix Theory: per(A)

        AUTHOR:
            - Jaap Spies (2006-02-19)
        """
        m = self._nrows
        n = self._ncols
        if not m <= n:
            raise ValueError, "must have m <= n, but m (=%s) and n (=%s)"%(m,n)

        R = self._base_ring
        if k == 0:
            return R(1)
        if k > m:
            return R(0)

        pm = 0
        for cols in _choose(n,k):
            for rows in _choose(m,k):
                pm = pm + self.matrix_from_rows_and_columns(rows, cols).permanent()
        return pm


    def rook_vector(self, check = False):
        r"""
        Returns rook vector of this matrix.

        Let $A$ be a general $m$ by $n$ (0,1)-matrix with $m \le n$.
        We identify $A$ with a chessboard where rooks can be placed on
        the fields corresponding with $a_{ij} = 1$. The number $r_k =
        p_k(A)$ (the permanental $k$-minor) counts the number of ways
        to place $k$ rooks on this board so that no two rooks can
        attack another.

        The rook vector is the list consisting of $r_0, r_1, \ldots, r_m$.

        The rook polynomial is defined by $r(x) = \sum_{k=0}^m r_k x^k$.

        INPUT:
            self -- m by n matrix with m <= n 
            check -- True or False (default), optional

        OUTPUT:
            rook vector

        EXAMPLES:
            sage: M = MatrixSpace(ZZ,3,6)
            sage: A = M([1,1,1,1,0,0,0,1,1,1,1,0,0,0,1,1,1,1])
            sage: A.rook_vector()
            [1, 12, 40, 36]

            sage: R.<x> = PolynomialRing(ZZ)
            sage: rv = A.rook_vector()
            sage: rook_polynomial = sum([rv[k] * x^k for k in range(len(rv))])
            sage: rook_polynomial
            36*x^3 + 40*x^2 + 12*x + 1

        AUTHOR:
            - Jaap Spies (2006-02-24)
        """
        m = self._nrows
        n = self._ncols
        if not m <= n:
            raise ValueError, "must have m <= n, but m (=%s) and n (=%s)"%(m,n)

        if check:
            # verify that self[i, j] in {0, 1}
            for i in range(m):
                for j in range(n):
                    x = self.get_unsafe(i, j)
                    if not (x == 0 or x == 1):
                        raise ValueError, "must have zero or one, but we have (=%s)"%x

        tmp = []
        for k in range(m+1):
            tmp.append(self.permanental_minor(k))
        return tmp

    def minors(self,k):
        """
        Return the list of all k-minors of self.

        Let A be an m x n matrix and k an integer with 0 < k, k <= m, and
        k <= n. A k x k minor of A is the determinant of a k x k matrix
        obtained from A by deleting m - k rows and n - k columns.

        The returned list is sorted in lexicographical row major ordering,
        e.g., if A is a 3 x 3 matrix then the minors returned are with
        for these rows/columns:  [ [0, 1]x[0, 1], [0, 1]x[0, 2],
        [0, 1]x[1, 2], [0, 2]x[0, 1], [0, 2]x[0, 2], [0, 2]x[1, 2],
        [1, 2]x[0, 1], [1, 2]x[0, 2], [1, 2]x[1, 2] ].

        INPUT:
            k -- integer

        EXAMPLE:
            sage: A = Matrix(ZZ,2,3,[1,2,3,4,5,6]); A
            [1 2 3]
            [4 5 6]
            sage: A.minors(2)
            [-3, -6, -3]
            
            sage: k = GF(37)
            sage: P.<x0,x1,x2> = PolynomialRing(k)
            sage: A = Matrix(P,2,3,[x0*x1, x0, x1, x2, x2 + 16, x2 + 5*x1 ])
            sage: A.minors(2)
            [x0*x1*x2 + 16*x0*x1 - x0*x2, 5*x0*x1^2 + x0*x1*x2 - x1*x2, 5*x0*x1 + x0*x2 - x1*x2 - 16*x1]
        """
        from sage.combinat.combinat import combinations_iterator
        all_rows = range(self.nrows())
        all_cols = range(self.ncols())
        m = []
        for rows in combinations_iterator(all_rows,k):
            for cols in combinations_iterator(all_cols,k):
                m.append(self.matrix_from_rows_and_columns(rows,cols).determinant())
        return m

    def determinant(self, algorithm="hessenberg"):
        r"""
        Return the determinant of self.

        ALGORITHM: For small matrices (n<4), this is computed using the naive formula
        For integral domains, the charpoly is computed (using hessenberg form)
        Otherwise this is computed using the very stupid expansion by
        minors stupid \emph{naive generic algorithm}.  For matrices
        over more most rings more sophisticated algorithms can be
        used.  (Type \code{A.determinant?} to see what is done for a
        specific matrix A.)

        EXAMPLES:
            sage: A = MatrixSpace(Integers(8),3)([1,7,3, 1,1,1, 3,4,5])
            sage: A.determinant()
            6
            sage: A.determinant() is A.determinant()
            True
            sage: A[0,0] = 10
            sage: A.determinant()
            7

        We compute the determinant of the arbitrary 3x3 matrix:
            sage: R = PolynomialRing(QQ,9,'x')
            sage: A = matrix(R,3,R.gens())
            sage: A
            [x0 x1 x2]
            [x3 x4 x5]
            [x6 x7 x8]
            sage: A.determinant()
            -x2*x4*x6 + x1*x5*x6 + x2*x3*x7 - x0*x5*x7 - x1*x3*x8 + x0*x4*x8

        We create a matrix over $\Z[x,y]$ and compute its determinant.
            sage: R.<x,y> = MPolynomialRing(IntegerRing(),2)
            sage: A = MatrixSpace(R,2)([x, y, x**2, y**2])
            sage: A.determinant()
            -x^2*y + x*y^2
            
        TEST:
            sage: A = matrix(5, 5, [next_prime(i^2) for i in range(25)])
            sage: B = MatrixSpace(ZZ['x'], 5, 5)(A)
            sage: A.det() - B.det()
            0
        """
        if self._nrows != self._ncols:
            raise ValueError, "self must be square"

        d = self.fetch('det')
        if not d is None: return d

        cdef Py_ssize_t i, n

        # if charpoly known, then det is easy.
        D = self.fetch('charpoly')
        if not D is None:
            c = D[D.keys()[0]][0]
            if self._nrows % 2 != 0:
                c = -c
            d = self._coerce_element(c)
            self.cache('det', d)
            return d

        n = self._ncols
        R = self._base_ring
            
        # For small matrices, you can't beat the naive formula
        if n <=  3:
            if n == 0:
                d = R(1)
            elif n == 1:
                d = self.get_unsafe(0,0)
            elif n == 2:
                d = self.get_unsafe(0,0)*self.get_unsafe(1,1) - self.get_unsafe(1,0)*self.get_unsafe(0,1)
            elif n == 3:
                d = self.get_unsafe(0,0) * (self.get_unsafe(1,1)*self.get_unsafe(2,2) - self.get_unsafe(1,2)*self.get_unsafe(2,1))    \
                    - self.get_unsafe(1,0) * (self.get_unsafe(0,1)*self.get_unsafe(2,2) - self.get_unsafe(0,2)*self.get_unsafe(2,1))  \
                    + self.get_unsafe(2,0) * (self.get_unsafe(0,1)*self.get_unsafe(1,2) - self.get_unsafe(0,2)*self.get_unsafe(1,1))
            self.cache('det', d)
            return d

        # if over an exact integral domain, we could get the det by computing charpoly.
        # Generic fraction field implementation is so slow that the naive algorithm is 
        # is much faster in practice despite asymptotics. 
        # TODO: find reasonable cutoff (Field specific, but seems to be quite large for Q[x])
        # if R.is_integral_domain() and R.is_exact() and algorithm == "hessenberg":
        if  R.is_field() and R.is_exact() and algorithm == "hessenberg":
            c = self.charpoly('x')[0]
            if self._nrows % 2:
                c = -c
            d = self._coerce_element(c)
            self.cache('det', d)
            return d

        # fall back to very very stupid algorithm -- expansion by minors.
        # TODO: surely there is something much better, even in total generality...
        # this is ridiculous.
        d = self._det_by_minors(self._ncols)
        self.cache('det', d)
        return d
        
    cdef _det_by_minors(self, Py_ssize_t level):
        """
        Compute the determinant of the upper-left level x level submatrix of self. 
        Does not handle degenerate cases, level MUST be >= 2
        """
        cdef Py_ssize_t n, i
        if level == 2:
            return self.get_unsafe(0,0) * self.get_unsafe(1,1) - self.get_unsafe(0,1) * self.get_unsafe(1,0)
        else:
            level -= 1
            d = self.get_unsafe(level,level) * self._det_by_minors(level)
            # on each iteration, row i will be missing in the first (level) rows
            # swapping is much faster than taking submatrices
            for i from level > i >= 0:
                self.swap_rows(level, i)
                if (level - i) % 2:
                    d -= self.get_unsafe(level,level) * self._det_by_minors(level)
                else:
                     d += self.get_unsafe(level,level) * self._det_by_minors(level)
            # undo all our permutations to get us back to where we started
            for i from 0 <= i < level:
                self.swap_rows(level, i)
            return d        


    # shortcuts
    def det(self, *args, **kwds):
        """
        Synonym for self.determinant(...).

        EXAMPLES:
            sage: A = MatrixSpace(Integers(8),3)([1,7,3, 1,1,1, 3,4,5])
            sage: A.det()
            6
        """
        return self.determinant(*args, **kwds)

    def __abs__(self):
        """
        Synonym for self.determinant(...).

        EXAMPLES:
            sage: a = matrix(QQ, 2,2, [1,2,3,4]); a
            [1 2]
            [3 4]
            sage: abs(a)
            -2
        """
        return self.determinant()

    def characteristic_polynomial(self, *args, **kwds):
        """
        Synonym for self.charpoly(...).

        EXAMPLES:
            sage: a = matrix(QQ, 2,2, [1,2,3,4]); a
            [1 2]
            [3 4]
            sage: a.characteristic_polynomial('T')
            T^2 - 5*T - 2
        """
        return self.charpoly(*args, **kwds)

    def minimal_polynomial(self, var='x', **kwds):
        r"""
        This is a synonym for \code{self.minpoly}

        EXAMPLES:
            sage: a = matrix(QQ, 4, range(16))
            sage: a.minimal_polynomial('z')
            z^3 - 30*z^2 - 80*z
            sage: a.minpoly()
            x^3 - 30*x^2 - 80*x
        """
        return self.minpoly(var, **kwds)

    def minpoly(self, var='x', **kwds):
        r"""
        Return the minimal polynomial of self.

        This uses a simplistic -- and potentially very very slow --
        algorithm that involves computing kernels to determine the
        powers of the factors of the charpoly that divide the minpoly.
        
        EXAMPLES:
            sage: A = matrix(GF(9,'c'), 4, [1, 1, 0,0, 0,1,0,0, 0,0,5,0, 0,0,0,5])
            sage: factor(A.minpoly())
            (x + 1) * (x + 2)^2
            sage: A.minpoly()(A) == 0
            True
            sage: factor(A.charpoly())
            (x + 1)^2 * (x + 2)^2

        The default variable name is $x$, but you can specify another name:
            sage: factor(A.minpoly('y'))
            (y + 1) * (y + 2)^2
        """
        f = self.fetch('minpoly')
        if not f is None:
            return f.change_variable_name(var)
        f = self.charpoly(var=var, **kwds)
        if f.is_squarefree():  # is_squarefree for polys much faster than factor.
            # Then f must be the minpoly
            self.cache('minpoly', f)
            return f

        # Now we have to work harder.  We find the power of each
        # irreducible factor that divides the minpoly.
        mp = f.radical()
        for h, e in f.factor():
            if e > 1:
                # Find the power of B so that the dimension
                # of the kernel equals e*deg(h)
                B = h(self)   # this is the killer.
                C = B
                n = 1
                while C.kernel().dimension() < e*h.degree():
                    if n == e - 1:
                        n += 1
                        break
                    C *= B
                    n += 1
                mp *= h**(n-1)
        self.cache('minpoly', mp)
        return mp
    

    def charpoly(self, var='x', algorithm="hessenberg"):
        r"""
        Return the characteristic polynomial of self, as a polynomial
        over the base ring.

        ALGORITHM: Compute the Hessenberg form of the matrix and read
        off the characteristic polynomial from that.  The result is
        cached.

        INPUT:
            var -- a variable name (default: 'x')
            algorithm -- string:
                  'hessenberg' -- default (use Hessenberg form of matrix)

        EXAMPLES:
        First a matrix over $\Z$:
            sage: A = MatrixSpace(ZZ,2)( [1,2,  3,4] )
            sage: f = A.charpoly('x')
            sage: f
            x^2 - 5*x - 2
            sage: f.parent()
            Univariate Polynomial Ring in x over Integer Ring
            sage: f(A)
            [0 0]
            [0 0]

        An example over $\Q$:
            sage: A = MatrixSpace(QQ,3)(range(9))
            sage: A.charpoly('x')
            x^3 - 12*x^2 - 18*x
            sage: A.trace()
            12
            sage: A.determinant()
            0

        We compute the characteristic polynomial of a matrix over
        the polynomial ring $\Z[a]$:
            sage: R.<a> = PolynomialRing(ZZ)
            sage: M = MatrixSpace(R,2)([a,1,  a,a+1]); M
            [    a     1]
            [    a a + 1]
            sage: f = M.charpoly('x'); f
            x^2 + (-2*a - 1)*x + a^2
            sage: f.parent()
            Univariate Polynomial Ring in x over Univariate Polynomial Ring in a over Integer Ring
            sage: M.trace()
            2*a + 1
            sage: M.determinant()
            a^2

        We compute the characteristic polynomial of a matrix over the
        multi-variate polynomial ring $\Z[x,y]$:
            sage: R.<x,y> = MPolynomialRing(ZZ,2)
            sage: A = MatrixSpace(R,2)([x, y, x^2, y^2])
            sage: f = A.charpoly('x'); f
            x^2 + (-y^2 - x)*x - x^2*y + x*y^2

        It's a little difficult to distinguish the variables.  To fix this,
        we temporarily view the indeterminate as $Z$:
            sage: with localvars(f.parent(), 'Z'): print f
            Z^2 + (-y^2 - x)*Z - x^2*y + x*y^2

        We could also compute f in terms of Z from the start:
            sage: A.charpoly('Z')
            Z^2 + (-y^2 - x)*Z - x^2*y + x*y^2

        TESTS:
            sage: P.<a,b,c> = PolynomialRing(Rationals())
            sage: u = MatrixSpace(P,3)([[0,0,a],[1,0,b],[0,1,c]])
            sage: Q.<x> = PolynomialRing(P)
            sage: u.charpoly('x')
            x^3 + (-c)*x^2 + (-b)*x - a
        """
        D = self.fetch('charpoly')
        if not D is None:
            if D.has_key(var):
                return D[var]
        else:
            D = {}
            self.cache('charpoly',D)
            
        f = self._charpoly_hessenberg(var)
        D[var] = f   # this caches it.
        return f


    def fcp(self, var='x'):
        """
        Return the factorization of the characteristic polynomial of self.

        INPUT:
            var -- (default: 'x') name of variable of charpoly
            
        EXAMPLES:
            sage: M = MatrixSpace(QQ,3,3)
            sage: A = M([1,9,-7,4/5,4,3,6,4,3])
            sage: A.fcp()
            x^3 - 8*x^2 + 209/5*x - 286
            sage: A = M([3, 0, -2, 0, -2, 0, 0, 0, 0])
            sage: A.fcp('T')
            (T - 3) * T * (T + 2)
        """
        return self.charpoly(var).factor()

##     def minimal_polynomial(self, var, algorithm=''):
##         """
##         Synonym for self.charpoly(...).

##         EXAMPLES:
##             sage: ???
##         """
##         return self.minpoly(*args, **kwds)

##     def minpoly(self, *args, **kwds):
##         """
##         EXAMPLES:
##             sage: ???
##         """
##         raise NotImplementedError

    def denominator(self):
        r"""
        Return the least common multiple of the denominators of the
        elements of self.

        If there is no denominator function for the base field, or no
        LCM function for the denominators, raise a TypeError.

        EXAMPLES:
            sage: A = MatrixSpace(QQ,2)(['1/2', '1/3', '1/5', '1/7'])
            sage: A.denominator()
            210

        A trivial example:
            sage: A = matrix(QQ, 0,2)
            sage: A.denominator()
            1

        Denominators are not defined for real numbers:
            sage: A = MatrixSpace(RealField(),2)([1,2,3,4])
            sage: A.denominator()
            Traceback (most recent call last):
            ...
            TypeError: denominator not defined for elements of the base ring

        We can even compute the denominator of matrix over the fraction field
        of $\Z[x]$.
            sage: K.<x> = Frac(ZZ['x'])
            sage: A = MatrixSpace(K,2)([1/x, 2/(x+1), 1, 5/(x^3)])
            sage: A.denominator()
            x^4 + x^3

        Here's an example involving a cyclotomic field:
            sage: K.<z> = CyclotomicField(3)
            sage: M = MatrixSpace(K,3,sparse=True)
            sage: A = M([(1+z)/3,(2+z)/3,z/3,1,1+z,-2,1,5,-1+z])
            sage: print A
            [1/3*z + 1/3 1/3*z + 2/3       1/3*z]
            [          1       z + 1          -2]
            [          1           5       z - 1]
            sage: print A.denominator()
            3
        """
        if self.nrows() == 0 or self.ncols() == 0:
            return ZZ(1)
        R = self.base_ring()
        x = self.list()
        try:
            d = x[0].denominator()
        except AttributeError:
            raise TypeError, "denominator not defined for elements of the base ring"
        try:
            for y in x:
                d = d.lcm(y.denominator())
        except AttributeError:
            raise TypeError, "lcm function not defined for elements of the base ring"
        return d


    def trace(self):
        """
        Return the trace of self, which is the sum of the
        diagonal entries of self.

        INPUT:
            self -- a square matrix
        OUTPUT:
            element of the base ring of self
        EXAMPLES:
            sage: a = matrix(3,range(9)); a
            [0 1 2]
            [3 4 5]
            [6 7 8]            
            sage: a.trace()
            12
            sage: a = matrix({(1,1):10, (2,1):-3, (2,2):4/3}); a
            [  0   0   0]
            [  0  10   0]
            [  0  -3 4/3]
            sage: a.trace()
            34/3
        """
        if self._nrows != self._ncols:
            raise ArithmeticError, "matrix must be square"
        R = self._base_ring
        cdef Py_ssize_t i
        cdef object s
        s = R(0)
        for i from 0 <= i < self._nrows:
            s = s + self.get_unsafe(i,i)
        return s

    #####################################################################################
    # Generic Hessenberg Form and charpoly algorithm
    #####################################################################################
    def hessenberg_form(self):
        """
        Return Hessenberg form of self.

        If the base ring is merely an integral domain (and not a
        field), the Hessenberg form will (in general) only be defined
        over the fraction field of the base ring.

        EXAMPLES:
            sage: A = matrix(ZZ,4,[2, 1, 1, -2, 2, 2, -1, -1, -1,1,2,3,4,5,6,7])
            sage: h = A.hessenberg_form(); h
            [    2  -7/2 -19/5    -2]
            [    2   1/2 -17/5    -1]
            [    0  25/4  15/2   5/2]
            [    0     0  58/5     3]
            sage: parent(h)
            Full MatrixSpace of 4 by 4 dense matrices over Rational Field
            sage: A.hessenbergize()
            Traceback (most recent call last):
            ...
            TypeError: Hessenbergize only possible for matrices over a field        
        """
        X = self.fetch('hessenberg_form')
        if not X is None:
            return X
        R = self._base_ring
        if not R.is_field():
            try:
                K = self._base_ring.fraction_field()
                H = self.change_ring(K)
                H.hessenbergize()
            except TypeError, msg:
                raise TypeError, "%s\nHessenberg form only possible for matrices over a field"%msg
        else:
            H = self.copy()
            H.hessenbergize()
        #end if
        self.cache('hessenberg_form', H)
        return H

    def hessenbergize(self):
        """
        Transform self to Hessenberg form.

        The hessenberg form of a matrix $A$ is a matrix that is
        similar to $A$, so has the same characteristic polynomial as
        $A$, and is upper triangular except possible for entries right
        below the diagonal.

        ALGORITHM: See Henri Cohen's first book.

        EXAMPLES:
            sage: A = matrix(QQ,3, [2, 1, 1, -2, 2, 2, -1, -1, -1])
            sage: A.hessenbergize(); A
            [  2 3/2   1]
            [ -2   3   2]
            [  0  -3  -2]

            sage: A = matrix(QQ,4, [2, 1, 1, -2, 2, 2, -1, -1, -1,1,2,3,4,5,6,7])
            sage: A.hessenbergize(); A
            [    2  -7/2 -19/5    -2]
            [    2   1/2 -17/5    -1]
            [    0  25/4  15/2   5/2]
            [    0     0  58/5     3]

        You can't Hessenbergize an immutable matrix:
            sage: A = matrix(QQ, 3, [1..9])
            sage: A.set_immutable()
            sage: A.hessenbergize()
            Traceback (most recent call last):
            ...
            ValueError: matrix is immutable; please change a copy instead (use self.copy()).
        """
        cdef Py_ssize_t i, j, m, n, r
        n = self._nrows

        tm = verbose("Computing Hessenberg Normal Form of %sx%s matrix"%(n,n))

        if not self.is_square():
            raise TypeError, "self must be square"

        if not self._base_ring.is_field():
            raise TypeError, "Hessenbergize only possible for matrices over a field"

        self.check_mutability()

        zero = self._base_ring(0)
        one = self._base_ring(1)
        for m from 1 <= m < n-1:
            # Search for a non-zero entry in column m-1
            i = -1
            for r from m+1 <= r < n:
                if self.get_unsafe(r, m-1) != zero:
                    i = r
                    break
            if i != -1: 
                # Found a nonzero entry in column m-1 that is strictly below row m
                # Now set i to be the first nonzero position >= m in column m-1
                if self.get_unsafe(m,m-1) != zero:
                    i = m
                t = self.get_unsafe(i,m-1)
                t_inv = None
                if i > m:
                    self.swap_rows_c(i,m)
                    # We must do the corresponding column swap to 
                    # maintain the characteristic polynomial (which is
                    # an invariant of Hessenberg form)
                    self.swap_columns_c(i,m)  
                # Now the nonzero entry in position (m,m-1) is t.
                # Use t to clear the entries in column m-1 below m.
                for j from m+1 <= j < n:
                    x = self.get_unsafe(j, m-1)
                    if x != zero:
                        if t_inv is None:
                            t_inv = one / t  
                        u = x * t_inv
                        self.add_multiple_of_row_c(j, m, -u, 0)
                        # To maintain charpoly, do the corresponding column operation,
                        # which doesn't mess up the matrix, since it only changes
                        # column m, and we're only worried about column m-1 right now.
                        # Add u*column_j to column_m.
                        self.add_multiple_of_column_c(m, j, u, 0)
        verbose("Finished Hessenberg Normal Form of %sx%s matrix"%(n,n),tm)



    def _charpoly_hessenberg(self, var):
        """
        Transforms self in place to its Hessenberg form then computes
        and returns the coefficients of the characteristic polynomial of
        this matrix.

        INPUT:
            var -- name of the indeterminate of the charpoly.

        The characteristic polynomial is represented as a vector of
        ints, where the constant term of the characteristic polynomial
        is the 0th coefficient of the vector.

        EXAMPLES:
            sage: matrix(QQ,3,range(9))._charpoly_hessenberg('Z')
            Z^3 - 12*Z^2 - 18*Z
            sage: matrix(ZZ,3,range(9))._charpoly_hessenberg('Z')
            Z^3 - 12*Z^2 - 18*Z
            sage: matrix(GF(7),3,range(9))._charpoly_hessenberg('Z')
            Z^3 + 2*Z^2 + 3*Z
            sage: matrix(QQ['x'],3,range(9))._charpoly_hessenberg('Z')
            Z^3 + (-12)*Z^2 + (-18)*Z
            sage: matrix(ZZ['ZZ'],3,range(9))._charpoly_hessenberg('Z')
            Z^3 + (-12)*Z^2 + (-18)*Z
        """
        if self._nrows != self._ncols:
            raise ArithmeticError, "charpoly not defined for non-square matrix."

        # Replace self by its Hessenberg form
        # (note the entries might now live in the fraction field)
        cdef Matrix H
        H = self.hessenberg_form()

        # We represent the intermediate polynomials that come up in
        # the calculations as rows of an (n+1)x(n+1) matrix, since
        # we've implemented basic arithmetic with such a matrix.
        # Please see the generic implementation of charpoly in
        # matrix.py to see more clearly how the following algorithm
        # actually works.  (The implementation is clearer (but slower)
        # if one uses polynomials to represent polynomials instead of
        # using the rows of a matrix.)  Also see Cohen's first GTM,
        # Algorithm 2.2.9.

        cdef Py_ssize_t i, m, n,
        n = self._nrows

        cdef Matrix c
        c = H.new_matrix(nrows=n+1,ncols=n+1)    # the 0 matrix
        one = H._coerce_element(1)
        c.set_unsafe(0,0,one)

        for m from 1 <= m <= n:
            # Set the m-th row of c to (x - H[m-1,m-1])*c[m-1] = x*c[m-1] - H[m-1,m-1]*c[m-1]
            # We do this by hand by setting the m-th row to c[m-1]
            # shifted to the right by one.  We then add
            # -H[m-1,m-1]*c[m-1] to the resulting m-th row.
            for i from 1 <= i <= n:
                c.set_unsafe(m, i, c.get_unsafe(m-1,i-1))
            c.add_multiple_of_row_c(m, m-1, -H.get_unsafe(m-1, m-1), 0)
            t = one
            for i from 1 <= i < m:
                t = t * H.get_unsafe(m-i,m-i-1)
                # Set the m-th row of c to c[m] - t*H[m-i-1,m-1]*c[m-i-1]
                c.add_multiple_of_row_c(m, m-i-1, - t*H.get_unsafe(m-i-1,m-1), 0)

        # The answer is now the n-th row of c.
        v = PyList_New(n+1)     # this is really sort of v = []..."
        for i from 0 <= i <= n:
            # Finally, set v[i] = c[n,i]            
            o = c.get_unsafe(n,i)
            Py_INCREF(o); PyList_SET_ITEM(v, i, o)

        R = self._base_ring[var]    # polynomial ring over the base ring
        return R(v)

    #####################################################################################
    # Decomposition: kernel, image, decomposition
    #####################################################################################
    nullity = left_nullity

    def left_nullity(self):
        """
        Return the (left) nullity of this matrix, which is the dimension
        of the (left) kernel of this matrix acting from the right on
        row vectors. 
        
        EXAMPLES:
            sage: M = Matrix(QQ,[[1,0,0,1],[0,1,1,0],[1,1,1,0]])
            sage: M.nullity()
            0
            sage: M.left_nullity()
            0            

            sage: A = M.transpose()
            sage: A.nullity()
            1
            sage: A.left_nullity()
            1
            
            sage: M = M.change_ring(ZZ)
            sage: M.nullity()
            0
            sage: A = M.transpose()
            sage: A.nullity()
            1
        """
        # Use that rank + nullity = number of rows, since matrices act
        # from the right on row vectors.
        return self.nrows() - self.rank()

    def right_nullity(self):
        """
        Return the right nullity of this matrix, which is the dimension
        of the right kernel.

        EXAMPLES:
            sage: A = MatrixSpace(QQ,3,2)(range(6))
            sage: A.right_nullity()
            0

            sage: A = matrix(ZZ,3,range(9))
            sage: A.right_nullity()
            1
        """
        return self.transpose().nullity()

    kernel = left_kernel
    
    def left_kernel(self, *args, **kwds):
        r"""
        Return the (left) kernel of this matrix, as a vector space.
        This is the space of vectors x such that x*self=0.
        Use self.right_kernel() for the right kernel.

        INPUT:
            -- all additional arguments to the kernel function
               are passed directly onto the echelon call.

        By convention if self has 0 rows, the kernel is of dimension
        0, whereas the kernel is whole domain if self has 0 columns.

        \algorithm{Elementary row operations don't change the kernel,
        since they are just right multiplication by an invertible
        matrix, so we instead compute kernel of the column echelon
        form.  More precisely, there is a basis vector of the kernel
        that corresponds to each non-pivot row.  That vector has a 1
        at the non-pivot row, 0's at all other non-pivot rows, and for
        each pivot row, the negative of the entry at the non-pivot row
        in the column with that pivot element.}

        \note{Since we view matrices as acting on the right, but have
        functions for reduced \emph{row} echelon forms, we instead
        compute the reduced row echelon form of the transpose of this
        matrix, which is the reduced column echelon form.}

        EXAMPLES:

        A kernel of dimension one over $\Q$:
            sage: A = MatrixSpace(QQ, 3)(range(9))
            sage: A.kernel()
            Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [ 1 -2  1]

        A trivial kernel:
            sage: A = MatrixSpace(QQ, 2)([1,2,3,4])
            sage: A.kernel()
            Vector space of degree 2 and dimension 0 over Rational Field
            Basis matrix:
            []

        Kernel of a zero matrix:
            sage: A = MatrixSpace(QQ, 2)(0)
            sage: A.kernel()
            Vector space of degree 2 and dimension 2 over Rational Field
            Basis matrix:
            [1 0]
            [0 1]

        Kernel of a non-square matrix:
            sage: A = MatrixSpace(QQ,3,2)(range(6))
            sage: A.kernel()
            Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [ 1 -2  1]

        The 2-dimensional kernel of a matrix over a cyclotomic field:
            sage: K = CyclotomicField(12); a=K.0
            sage: M = MatrixSpace(K,4,2)([1,-1, 0,-2, 0,-a**2-1, 0,a**2-1])
            sage: M
            [             1             -1]
            [             0             -2]
            [             0 -zeta12^2 - 1]
            [             0  zeta12^2 - 1]
            sage: M.kernel()
            Vector space of degree 4 and dimension 2 over Cyclotomic Field of order 12 and degree 4
            Basis matrix:
            [               0                1                0     -2*zeta12^2]
            [               0                0                1 -2*zeta12^2 + 1]

        A nontrivial kernel over a complicated base field.
            sage: K = FractionField(MPolynomialRing(QQ, 2, 'x'))
            sage: M = MatrixSpace(K, 2)([[K.1, K.0], [K.1, K.0]])
            sage: M
            [x1 x0]
            [x1 x0]
            sage: M.kernel()
            Vector space of degree 2 and dimension 1 over Fraction Field of Multivariate Polynomial Ring in x0, x1 over Rational Field
            Basis matrix:
            [ 1 -1]
        """
        K = self.fetch('left_kernel')
        if not K is None:
            return K
        R = self._base_ring

        if self._nrows == 0:    # from a degree-0 space
            V = sage.modules.free_module.VectorSpace(R, self._nrows)
            Z = V.zero_subspace()
            self.cache('left_kernel', Z)
            return Z

        elif self._ncols == 0:  # to a degree-0 space
            Z = sage.modules.free_module.VectorSpace(R, self._nrows)
            self.cache('left_kernel', Z)
            return Z

        if is_NumberField(R):
            A = self._pari_().mattranspose()
            B = A.matker()
            n = self._nrows
            V = sage.modules.free_module.VectorSpace(R, n)
            basis = [V([R(x) for x in b]) for b in B]
            Z = V.subspace(basis)
            self.cache('left_kernel', Z)
            return Z

        E = self.transpose().echelon_form(*args, **kwds)
        pivots = E.pivots()
        pivots_set = set(pivots)
        basis = []
        VS = sage.modules.free_module.VectorSpace
        V = VS(R, self.nrows())
        ONE = R(1)
        for i in xrange(self._nrows):
            if not (i in pivots_set):
                v = V(0)
                v[i] = ONE
                for r in range(len(pivots)):
                    v[pivots[r]] = -E[r,i]
                basis.append(v)
        W = V.subspace(basis)
        if W.dimension() != len(basis):
            raise RuntimeError, "bug in kernel function in matrix2.pyx -- basis got from echelon form not a basis."
        self.cache('left_kernel', W)
        return W

    def right_kernel(self, *args, **kwds):
        r"""
        Return the right kernel of this matrix, as a vector space.
        This is the space of vectors x such that self*x=0.

        INPUT:
            -- all additional arguments to the kernel function
               are passed directly onto the echelon call.

        By convention if self has 0 columns, the kernel is of dimension
        0, whereas the kernel is whole domain if self has 0 rows.

        EXAMPLES:

        A kernel of dimension one over $\Q$:
            sage: A = MatrixSpace(QQ, 3)(range(9))
            sage: A.right_kernel()
            Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [ 1 -2  1]

        A trivial kernel:
            sage: A = MatrixSpace(QQ, 2)([1,2,3,4])
            sage: A.right_kernel()
            Vector space of degree 2 and dimension 0 over Rational Field
            Basis matrix:
            []

        Kernel of a zero matrix:
            sage: A = MatrixSpace(QQ, 2)(0)
            sage: A.right_kernel()
            Vector space of degree 2 and dimension 2 over Rational Field
            Basis matrix:
            [1 0]
            [0 1]

        Kernel of a non-square matrix:
            sage: A = MatrixSpace(QQ,2,3)(range(6))
            sage: A.right_kernel()
            Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [ 1 -2  1]

        The 2-dimensional kernel of a matrix over a cyclotomic field:
            sage: K = CyclotomicField(12); a=K.0
            sage: M = MatrixSpace(K,2,4)([1,-1, 0,-2, 0,-a**2-1, 0,a**2-1])
            sage: M
            [            1            -1             0            -2]
            [            0 -zeta12^2 - 1             0  zeta12^2 - 1]
            sage: M.right_kernel()
            Vector space of degree 4 and dimension 2 over Cyclotomic Field of order 12 and degree 4
            Basis matrix:
            [      1  4/13*zeta12^2 - 1/13      0 -2/13*zeta12^2 + 7/13]
            [      0                     0      1                     0]

        A nontrivial kernel over a complicated base field.
            sage: K = FractionField(MPolynomialRing(QQ, 2, 'x'))
            sage: M = MatrixSpace(K, 2)([[K.1, K.0], [K.1, K.0]])
            sage: M
            [x1 x0]
            [x1 x0]
            sage: M.right_kernel()
            Vector space of degree 2 and dimension 1 over Fraction Field of Multivariate Polynomial Ring in x0, x1 over Rational Field
            Basis matrix:
            [ 1 x1/(-x0)]
        """
        K = self.fetch('right_kernel')
        if not K is None:
            return K

        K = self.transpose().kernel(*args, **kwds)
        self.cache('right_kernel', K)
        return K

        
    def kernel_on(self, V, poly=None, check=True):
        """
        Return the kernel of self restricted to the invariant subspace V.
        The result is a vector subspace of V, which is also a subspace
        of the ambient space.

        INPUT:
            V -- vector subspace
            check -- (optional) default: True; whether to check that
                     V is invariant under the action of self.
            poly -- (optional) default: None; if not None, compute instead
                    the kernel of poly(self) on V. 

        OUTPUT:
            a subspace

        WARNING: This function does \emph{not} check that V is in fact
        invariant under self if check is False.  With check False this
        function is much faster. 

        EXAMPLES:
            sage: t = matrix(QQ, 4, [39, -10, 0, -12, 0, 2, 0, -1, 0, 1, -2, 0, 0, 2, 0, -2]); t
            [ 39 -10   0 -12]
            [  0   2   0  -1]
            [  0   1  -2   0]
            [  0   2   0  -2]
            sage: t.fcp()
            (x - 39) * (x + 2) * (x^2 - 2)
            sage: s = (t-39)*(t^2-2)
            sage: V = s.kernel(); V
            Vector space of degree 4 and dimension 3 over Rational Field
            Basis matrix:
            [1 0 0 0]
            [0 1 0 0]
            [0 0 0 1]
            sage: s.restrict(V)
            [0 0 0]
            [0 0 0]
            [0 0 0]
            sage: s.kernel_on(V)
            Vector space of degree 4 and dimension 3 over Rational Field
            Basis matrix:
            [1 0 0 0]
            [0 1 0 0]
            [0 0 0 1]
            sage: k = t-39
            sage: k.restrict(V)
            [  0 -10 -12]
            [  0 -37  -1]
            [  0   2 -41]
            sage: ker = k.kernel_on(V); ker
            Vector space of degree 4 and dimension 1 over Rational Field
            Basis matrix:
            [   1 -2/7    0 -2/7]
            sage: ker.0 * k
            (0, 0, 0, 0)
        """
        A = self.restrict(V, check=check)
        if not poly is None:
            A = poly(A)
        W = A.kernel()
        if V.is_ambient():
            return W
        else:
            A = V.basis_matrix()
            B = W.basis_matrix()
            C = B*A
            return C.row_module()


    def integer_kernel(self):
        """
        Return the integral kernel of this matrix.

        Assume that the base field of this matrix has a numerator and
        denominator functions for its elements, e.g., it is the
        rational numbers or a fraction field.  This function computes
        a basis over the integers for the kernel of self.
        
        When kernels are implemented for matrices over general PID's,
        this function will compute kernels over PID's of matrices over
        the fraction field of the PID.  (todo)

        EXAMPLES:
            sage: A = MatrixSpace(QQ, 4)(range(16))
            sage: A.integer_kernel()
            Free module of degree 4 and rank 2 over Integer Ring
            Echelon basis matrix:
            [ 1  0 -3  2]
            [ 0  1 -2  1]

        The integer kernel even makes sense for matrices with
        fractional entries:
            sage: A = MatrixSpace(QQ, 2)(['1/2',0,  0, 0])
            sage: A.integer_kernel()
            Free module of degree 2 and rank 1 over Integer Ring
            Echelon basis matrix:
            [0 1]
        """
        try:
            A, _ = self._clear_denom()
            return A.kernel()
        except AttributeError:
            d = self.denominator()
            A = self*d
            R = d.parent()
            M = matrix_space.MatrixSpace(R, self.nrows(), self.ncols())(A)
            return M.kernel()

    def image(self):
        """
        Return the image of the homomorphism on rows defined by this matrix.

        EXAMPLES:
            sage: MS1 = MatrixSpace(ZZ,4)
            sage: MS2 = MatrixSpace(QQ,6)
            sage: A = MS1.matrix([3,4,5,6,7,3,8,10,14,5,6,7,2,2,10,9])
            sage: B = MS2.random_element()

            sage: image(A)
            Free module of degree 4 and rank 4 over Integer Ring
            Echelon basis matrix:
            [  1   0   0 426]
            [  0   1   0 518]
            [  0   0   1 293]
            [  0   0   0 687]

            sage: image(B) == B.row_module()
            True
        """
        return self.row_module()

    def _row_ambient_module(self, base_ring=None):
        if base_ring is None:
            base_ring = self.base_ring()
        x = self.fetch('row_ambient_module_%s'%base_ring)
        if not x is None:
            return x
        x = sage.modules.free_module.FreeModule(base_ring, self.ncols(), sparse=self.is_sparse())
        self.cache('row_ambient_module',x)
        return x

    def row_module(self, base_ring=None):
        """
        Return the free module over the base ring spanned by the rows
        of self.

        EXAMPLES:
            sage: A = MatrixSpace(IntegerRing(), 2)([1,2,3,4])
            sage: A.row_module()
            Free module of degree 2 and rank 2 over Integer Ring
            Echelon basis matrix:
            [1 0]
            [0 2]
        """
        M = self._row_ambient_module(base_ring = base_ring)
        if (base_ring is None or base_ring == self.base_ring()) and self.fetch('in_echelon_form'):
            if self.rank() != self.nrows():
                rows = self.matrix_from_rows(range(self.rank())).rows()
            else:
                rows = self.rows()
            return M.span(rows, already_echelonized=True)
        else:
            return M.span(self.rows(), already_echelonized=False)

    def row_space(self, base_ring=None):
        """
        Return the row space of this matrix.  (Synonym for self.row_module().)

        EXAMPLES:
            sage: t = matrix(QQ, 3, range(9)); t
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: t.row_space()
            Vector space of degree 3 and dimension 2 over Rational Field
            Basis matrix:
            [ 1  0 -1]
            [ 0  1  2]

            sage: m = Matrix(Integers(5),2,2,[2,2,2,2]);
            sage: m.row_space()
            Vector space of degree 2 and dimension 1 over Ring of integers modulo 5
            Basis matrix:
            [1 1]
        """
        return self.row_module(base_ring=base_ring)
    

    def _column_ambient_module(self):
        x = self.fetch('column_ambient_module')
        if not x is None:
            return x
        x = sage.modules.free_module.FreeModule(self.base_ring(), self.nrows(),
                                                sparse=self.is_sparse())
        self.cache('column_ambient_module',x)
        return x

    def column_module(self):
        """
        Return the free module over the base ring spanned by the
        columns of this matrix.

        EXAMPLES:
            sage: t = matrix(QQ, 3, range(9)); t
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: t.column_module()
            Vector space of degree 3 and dimension 2 over Rational Field
            Basis matrix:
            [ 1  0 -1]
            [ 0  1  2]        
        """
        return self.transpose().row_module()

    def column_space(self):
        """
        Return the vector space over the base ring spanned by the
        columns of this matrix.

        EXAMPLES:
            sage: M = MatrixSpace(QQ,3,3)
            sage: A = M([1,9,-7,4/5,4,3,6,4,3])        
            sage: A.column_space()
            Vector space of degree 3 and dimension 3 over Rational Field
            Basis matrix:
            [1 0 0]
            [0 1 0]
            [0 0 1]
            sage: W = MatrixSpace(CC,2,2)
            sage: B = W([1, 2+3*I,4+5*I,9]); B
            [                     1.00000000000000 2.00000000000000 + 3.00000000000000*I]
            [4.00000000000000 + 5.00000000000000*I                      9.00000000000000]
            sage: B.column_space()
            Vector space of degree 2 and dimension 2 over Complex Field with 53 bits of precision
            Basis matrix:
            [1.00000000000000                0]
            [               0 1.00000000000000]            
        """
        return self.column_module()
    


    def decomposition(self, algorithm='spin',
                      is_diagonalizable=False, dual=False):
        """
        Returns the decomposition of the free module on which this
        matrix A acts from the right (i.e., the action is x goes to x
        A), along with whether this matrix acts irreducibly on each
        factor.  The factors are guaranteed to be sorted in the same
        way as the corresponding factors of the characteristic
        polynomial.

        Let A be the matrix acting from the on the vector space V of
        column vectors.  Assume that A is square.  This function
        computes maximal subspaces W_1, ..., W_n corresponding to
        Galois conjugacy classes of eigenvalues of A.  More precisely,
        let f(X) be the characteristic polynomial of A.  This function
        computes the subspace $W_i = ker(g_(A)^n)$, where g_i(X) is an
        irreducible factor of f(X) and g_i(X) exactly divides f(X).
        If the optional parameter is_diagonalizable is True, then we
        let W_i = ker(g(A)), since then we know that ker(g(A)) =
        $ker(g(A)^n)$.

        INPUT:
            self -- a matrix
            algorithm -- 'spin' (default): algorithm involves iterating the action
                                   of self on a vector.
                         'kernel': naively just compute ker f_i(A)
                                   for each factor f_i.
            dual -- bool (default: False): If True, also returns the
                           corresponding decomposition of V under the action of
                           the transpose of A.  The factors are guaranteed
                           to correspond.
            is_diagonalizable -- if the matrix is known to be diagonalizable, set this to True,
                           which might speed up the algorithm in some cases.
                           
                                   
        NOTE: If the base ring is not a field, the kernel algorithm is used. 
                                          
        OUTPUT:
            Sequence -- list of pairs (V,t), where V is a vector spaces
                    and t is a bool, and t is True exactly when the
                    charpoly of self on V is irreducible.

            (optional) list -- list of pairs (W,t), where W is a vector
                    space and t is a bool, and t is True exactly
                    when the charpoly of the transpose of self on W
                    is irreducible.

        EXAMPLES:
            sage: A = matrix(ZZ, 4, [3,4,5,6,7,3,8,10,14,5,6,7,2,2,10,9])
            sage: B = matrix(QQ, 6, range(36))
            sage: B*11
            [  0  11  22  33  44  55]
            [ 66  77  88  99 110 121]
            [132 143 154 165 176 187]
            [198 209 220 231 242 253]
            [264 275 286 297 308 319]
            [330 341 352 363 374 385]
            sage: A.decomposition()
            [
            (Ambient free module of rank 4 over the principal ideal domain Integer Ring, True)
            ]           
            sage: B.decomposition()
            [
            (Vector space of degree 6 and dimension 2 over Rational Field
            Basis matrix:
            [ 1  0 -1 -2 -3 -4]
            [ 0  1  2  3  4  5], True),
            (Vector space of degree 6 and dimension 4 over Rational Field
            Basis matrix:
            [ 1  0  0  0 -5  4]
            [ 0  1  0  0 -4  3]
            [ 0  0  1  0 -3  2]
            [ 0  0  0  1 -2  1], False)
            ]
        """
        if algorithm == 'kernel' or not self.base_ring().is_field():
            return self._decomposition_using_kernels(is_diagonalizable = is_diagonalizable, dual=dual)
        elif algorithm == 'spin':
            X = self._decomposition_spin_generic(is_diagonalizable = is_diagonalizable)
            if dual:
                Y = self.transpose()._decomposition_spin_generic(is_diagonalizable = is_diagonalizable)
                return X, Y
            return X
        else:
            raise ValueError, "no algorithm '%s'"%algorithm

    def _decomposition_spin_generic(self, is_diagonalizable=False):
        r"""
        Compute the decomposition of this matrix using the spin algorithm.

        INPUT:
            self -- a matrix with field entries

        OUTPUT:
            a list of reduced row echelon form basis

        AUTHOR:
           -- William Stein
        """
        if not self.is_square():
            raise ArithmeticError, "self must be a square matrix"

        if not self.base_ring().is_field():
            raise TypeError, "self must be over a field."

        if self.nrows() == 0:
            return decomp_seq([])

        f = self.charpoly('x')
        E = decomp_seq([])

        t = verbose('factoring the characteristic polynomial', level=2, caller_name='generic spin decomp')
        F = f.factor()
        verbose('done factoring', t=t, level=2, caller_name='generic spin decomp')
        
        if len(F) == 1:
            V = self.base_ring()**self.nrows()
            return decomp_seq([(V,F[0][1]==1)])

        V = self.base_ring()**self.nrows()
        v = V.random_element()
        num_iterates = max([0] + [f.degree() - g.degree() for g, _ in F if g.degree() > 1]) + 1

        S = [ ]
        
        F.sort()
        for i in range(len(F)):
            g, m = F[i]

            if g.degree() == 1:
                # Just use kernel -- much easier.
                B = self.copy()
                for k from 0 <= k < self.nrows():
                    B[k,k] += g[0]
                if m > 1 and not is_diagonalizable:
                    B = B**m
                W = B.kernel()
                E.append((W, m==1))
                continue

            # General case, i.e., deg(g) > 1:
            W = None
            tries = m
            while True:

                # Compute the complementary factor.
                h = f // (g**m)
                v = h.list()

                while len(S) < tries:
                    t = verbose('%s-spinning %s-th random vector'%(num_iterates, len(S)), level=2, caller_name='generic spin decomp')
                    S.append(self.iterates(V.random_element(), num_iterates))
                    verbose('done spinning', level=2, t=t, caller_name='generic spin decomp')

                for j in range(0 if W is None else W.nrows() // g.degree(), len(S)):
                    # Compute one element of the kernel of g(A)**m.
                    t = verbose('compute element of kernel of g(A), for g of degree %s'%g.degree(),level=2,
                                caller_name='generic spin decomp')
                    w = S[j].linear_combination_of_rows(h.list())
                    t = verbose('done computing element of kernel of g(A)', t=t,level=2, caller_name='generic spin decomp')

                    # Get the rest of the kernel.
                    t = verbose('fill out rest of kernel',level=2, caller_name='generic spin decomp')
                    if W is None:
                        W = self.iterates(w, g.degree())
                    else:
                        W = W.stack(self.iterates(w, g.degree()))
                    t = verbose('finished filling out more of kernel',level=2, t=t, caller_name='generic spin decomp')
                    
                if W.rank() == m * g.degree():
                    t = verbose('now computing row space', level=2, caller_name='generic spin decomp')
                    W.echelonize()
                    E.append((W.row_space(), m==1))
                    verbose('computed row space', level=2,t=t, caller_name='generic spin decomp')
                    break
                else:
                    verbose('we have not yet generated all the kernel (rank so far=%s, target rank=%s)'%(
                        W.rank(), m*g.degree()), level=2, caller_name='generic spin decomp')
                    tries += 1
                    if tries > 1000*m:  # avoid an insanely long infinite loop
                        raise RuntimeError, "likely bug in decomposition"
                # end if
            #end while
        #end for
        return E

    def _decomposition_using_kernels(self, is_diagonalizable=False, dual=False):
        if not self.is_square():
            raise ArithmeticError, "self must be a square matrix"

        if self.nrows() == 0:
            return decomp_seq([])

        f = self.charpoly('x')
        E = decomp_seq([])

        # Idea: For optimization, could compute powers of self
        #       up to max degree of any factor.  Then get g(self)
        #       by taking a linear combination.   

        if dual:
            Edual = decomp_seq([])
        F = f.factor()
        if len(F) == 1:
            V = sage.modules.free_module.FreeModule(
                              self.base_ring(), self.nrows(), sparse=self.is_sparse()) 
            m = F[0][1]
            if dual:
                return decomp_seq([(V, m==1)]), decomp_seq([(V, m==1)])
            else:
                return decomp_seq([(V, m==1)])
        F.sort()
        for g, m in f.factor():
            t = verbose('decomposition -- Computing g(self) for an irreducible factor g of degree %s'%g.degree(),level=2)
            if is_diagonalizable:
                B = g(self)
            else:
                B = g(self)
                t2 = verbose('decomposition -- raising g(self) to the power %s'%m,level=2)
                B = B ** m
                verbose('done powering',t2)
            t = verbose('decomposition -- done computing g(self)', level=2, t=t)
            E.append((B.kernel(), m==1))
            t = verbose('decomposition -- time to compute kernel', level=2, t=t)
            if dual:
                Edual.append((B.transpose().kernel(), m==1))
                verbose('decomposition -- time to compute dual kernel', level=2, t=t)
        if dual:
            return E, Edual
        return E

    def decomposition_of_subspace(self, M, **kwds):
        """
        Suppose the right action of self on M leaves M
        invariant. Return the decomposition of M as a list of pairs
        (W, is_irred) where is_irred is True if the charpoly of self
        acting on the factor W is irreducible.

        Additional inputs besides M are passed onto the decomposition
        command.

        EXAMPLES:
            sage: t = matrix(QQ, 3, [3, 0, -2, 0, -2, 0, 0, 0, 0]); t
            [ 3  0 -2]
            [ 0 -2  0]
            [ 0  0  0]
            sage: t.fcp('X')   # factored charpoly
            (X - 3) * X * (X + 2)
            sage: v = kernel(t*(t+2)); v   # an invariant subspace
            Vector space of degree 3 and dimension 2 over Rational Field
            Basis matrix:
            [0 1 0]
            [0 0 1]
            sage: D = t.decomposition_of_subspace(v); D
            [
            (Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [0 0 1], True),
            (Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [0 1 0], True)
            ]
            sage: t.restrict(D[0][0])
            [0]
            sage: t.restrict(D[1][0])
            [-2]

        We do a decomposition over ZZ:
            sage: a = matrix(ZZ,6,[0, 0, -2, 0, 2, 0, 2, -4, -2, 0, 2, 0, 0, 0, -2, -2, 0, 0, 2, 0, -2, -4, 2, -2, 0, 2, 0, -2, -2, 0, 0, 2, 0, -2, 0, 0])
            sage: a.decomposition_of_subspace(ZZ^6)
            [
            (Free module of degree 6 and rank 2 over Integer Ring
            Echelon basis matrix:
            [ 1  0  1 -1  1 -1]
            [ 0  1  0 -1  2 -1], False),
            (Free module of degree 6 and rank 4 over Integer Ring
            Echelon basis matrix:
            [ 1  0 -1  0  1  0]
            [ 0  1  0  0  0  0]
            [ 0  0  0  1  0  0]
            [ 0  0  0  0  0  1], False)
            ]
        """
        if not sage.modules.free_module.is_FreeModule(M):
            raise TypeError, "M must be a free module."
        if not self.is_square():
            raise ArithmeticError, "matrix must be square"
        if M.base_ring() != self.base_ring():
            raise ArithmeticError, "base rings must be the same, but self is over %s and module is over %s"%(
                self.base_ring(), M.base_ring())
        if M.degree() != self.ncols():
            raise ArithmeticError, \
               "M must be a subspace of an %s-dimensional space"%self.ncols()

        time = verbose(t=0)

        # 1. Restrict
        B = self.restrict(M)
        time0 = verbose("decompose restriction -- ", time)

        # 2. Decompose restriction
        D = B.decomposition(**kwds)

        sum_dim = sum([A.dimension() for A,_ in D])
        assert sum_dim == M.dimension(), \
               "bug in decomposition; " + \
               "the sum of the dimensions (=%s) of the factors must equal the dimension (%s) of the acted on space:\nFactors found: %s\nSpace: %s"%(sum_dim, M.dimension(), D, M)

        # 3. Lift decomposition to subspaces of ambient vector space.
        # Each basis vector for an element of D defines a linear
        # combination of the basis of W, and these linear combinations
        # define the corresponding subspaces of the ambient space M.

        verbose("decomposition -- ", time0)        
        C = M.basis_matrix()

        D = [((W.basis_matrix() * C).row_module(self.base_ring()), is_irred) for W, is_irred in D]
        D = decomp_seq(D)

        verbose(t=time)
        return D

    def restrict(self, V, check=True):
        """
        Returns the matrix that defines the action of self on the
        chosen basis for the invariant subspace V.  If V is an
        ambient, returns self (not a copy of self).

        INPUT:
            V -- vector subspace
            check -- (optional) default: True; if False may not check
                     that V is invariant (hence can be faster). 
        OUTPUT:
            a matrix

        WARNING:
        This function returns an nxn matrix, where V has dimension n.
        It does \emph{not} check that V is in fact invariant under
        self, unless check is True.

        EXAMPLES:
            sage: V = VectorSpace(QQ, 3)
            sage: M = MatrixSpace(QQ, 3)
            sage: A = M([1,2,0, 3,4,0, 0,0,0])
            sage: W = V.subspace([[1,0,0], [0,1,0]])
            sage: A.restrict(W)
            [1 2]
            [3 4]
            sage: A.restrict(W, check=True)
            [1 2]
            [3 4]

        We illustrate the warning about invariance not being checked
        by default, by giving a non-invariant subspace.  With the default
        check=False this function returns the 'restriction' matrix, which
        is meaningless as check=True reveals.
            sage: W2 = V.subspace([[1,0,0], [0,1,1]])
            sage: A.restrict(W2, check=False)
            [1 2]
            [3 4]
            sage: A.restrict(W2, check=True)
            Traceback (most recent call last):
            ...
            ArithmeticError: subspace is not invariant under matrix
        """
        if not isinstance(V, sage.modules.free_module.FreeModule_generic):
            raise TypeError, "V must be a free module"
        #if V.base_ring() != self.base_ring():
        #     raise ValueError, "matrix and module must have the same base ring, but matrix is over %s and module is over %s"%(self.base_ring(), V.base_ring())
        if V.degree() != self.nrows():
            raise IndexError, "degree of V (=%s) must equal number of rows of self (=%s)"%(\
                V.degree(), self.nrows())
        if V.rank() == 0 or V.degree() == 0:
            return self.new_matrix(nrows=0, ncols=0)

        if not check and V.base_ring().is_field() and not V.has_user_basis():
            B = V.echelonized_basis_matrix()
            P = B.pivots()
            return B*self.matrix_from_columns(P)
        else:
            n = V.rank()
            try:
                # todo optimize so only involves matrix multiplies ?
                C = [V.coordinate_vector(b*self) for b in V.basis()]
            except ArithmeticError:
                raise ArithmeticError, "subspace is not invariant under matrix"
            return self.new_matrix(n, n, C, sparse=False)

    def restrict_domain(self, V):
        """
        Compute the matrix relative to the basis for V on the domain
        obtained by restricting self to V, but not changing the
        codomain of the matrix.  This is the matrix whose rows are the
        images of the basis for V.

        INPUT:
            V -- vector space (subspace of ambient space on which self acts)

        SEE ALSO: restrict()

        EXAMPLES:
            sage: V = QQ^3
            sage: A = matrix(QQ,3,[1,2,0, 3,4,0, 0,0,0])
            sage: W = V.subspace([[1,0,0], [1,2,3]])
            sage: A.restrict_domain(W)
            [1 2 0]
            [3 4 0]
            sage: W2 = V.subspace_with_basis([[1,0,0], [1,2,3]])
            sage: A.restrict_domain(W2)
            [ 1  2  0]
            [ 7 10  0]
        """
        return V.basis_matrix() * self

    def restrict_codomain(self, V):
        r"""
        Suppose that self defines a linear map from some domain to a
        codomain that contains $V$ and that the image of self is
        contained in $V$.  This function returns a new matrix $A$ that
        represents this linear map but as a map to $V$, in the sense
        that if $x$ is in the domain, then $xA$ is the linear
        combination of the elements of the basis of $V$ that equals
        v*self.
        
        INPUT:
            V -- vector space (space of degree \code{self.ncols()})
                 that contains the image of self.

        SEE ALSO: \code{restrict()}, \code{restrict_domain()}

        EXAMPLES:
            sage: A = matrix(QQ,3,[1..9])
            sage: V = (QQ^3).span([[1,2,3], [7,8,9]]); V
            Vector space of degree 3 and dimension 2 over Rational Field
            Basis matrix:
            [ 1  0 -1]
            [ 0  1  2]
            sage: z = vector(QQ,[1,2,5])
            sage: B = A.restrict_codomain(V); B
            [1 2]
            [4 5]
            [7 8]
            sage: z*B
            (44, 52)
            sage: z*A
            (44, 52, 60)
            sage: 44*V.0 + 52*V.1
            (44, 52, 60)
        """
        return V.basis_matrix().solve_left(self)

    def maxspin(self, v):
        """
        Computes the largest integer n such that the list of vectors
        $S=[v, v*A, ..., v * A^n]$ are linearly independent, and returns
        that list.

        INPUT:
            self -- Matrix
            v -- Vector
            
        OUTPUT:
            list -- list of Vectors

        ALGORITHM:
            The current implementation just adds vectors to a vector
            space until the dimension doesn't grow.  This could be
            optimized by directly using matrices and doing an
            efficient Echelon form.  Also, when the base is Q, maybe
            we could simultaneously keep track of what is going on in
            the reduction modulo p, which might make things much
            faster.

        EXAMPLES:
            sage: t = matrix(QQ, 3, range(9)); t
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: v = (QQ^3).0
            sage: t.maxspin(v)
            [(1, 0, 0), (0, 1, 2), (15, 18, 21)]
            sage: k = t.kernel(); k
            Vector space of degree 3 and dimension 1 over Rational Field
            Basis matrix:
            [ 1 -2  1]
            sage: t.maxspin(k.0)
            [(1, -2, 1)]        
        """
        if v == 0:
            return []
        if not is_FreeModuleElement(v):
            raise TypeError, "v must be a FreeModuleElement"
        VS = v.parent()
        V = VS.span([v])
        w = v
        S = [v]
        while True:
            w = w*self
            W = V + VS.span([w])
            if W.dimension() == V.dimension():
                return S
            V = W
            S.append(w)


    def wiedemann(self, i, t=0):
        """
        Application of Wiedemann's algorithm to the i-th standard
        basis vector.

        INPUT:
            i -- an integer
            t -- an integer (default: 0)  if t is nonzero, use only the first t
                 linear recurrence relations.

        IMPLEMENTATION: This is a toy implementation.

        EXAMPLES:
            sage: t = matrix(QQ, 3, range(9)); t
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: t.wiedemann(0)
            x^2 - 12*x - 18
            sage: t.charpoly()
            x^3 - 12*x^2 - 18*x
        """
        i = int(i); t=int(t)
        if self.nrows() != self.ncols():
            raise ArithmeticError, "matrix must be square."
        n = self.nrows()
        v = sage.modules.free_module.VectorSpace(self.base_ring(), n).gen(i)
        tm = verbose('computing iterates...')
        cols = self.iterates(v, 2*n).columns()
        tm = verbose('computed iterates', tm)
        f = None
        # Compute the minimal polynomial of the linear recurrence
        # sequence corresponding to the 0-th entries of the iterates,
        # then the 1-th entries, etc.
        if t == 0:
            R = range(n)
        else:
            R = [t]
        for i in R:
            tm = verbose('applying berlekamp-massey')
            g = berlekamp_massey.berlekamp_massey(cols[i].list())
            verbose('berlekamp-massey done', tm)
            if f is None:
                f = g
            else:
                f = f.lcm(g)
            if f.degree() == n:
                break
        return f
            

    def eigenspaces(self, var='a', even_if_inexact=False):
        r"""
        Return a list of pairs
             (e, V)
        where e runs through all eigenvalues (up to Galois conjugation)
        of this matrix, and V is the corresponding eigenspace.

        The eigenspaces are returned sorted by the corresponding characteristic
        polynomials, where polynomials are sorted in dictionary order starting
        with constant terms. 

        NOTE: 
            Calling this method of a matrix over an inexact base ring will
            raise a NotImplementedError.  If you want to force this anyway,
            pass the option even_if_inexact=True.
        

        INPUT:
            var -- variable name used to represent elements of
                   the root field of each irreducible factor of
                   the characteristic polynomial
                   I.e., if var='a', then the root fields
                   will be in terms of a0, a1, a2, ..., ak.

        WARNING: Uses a somewhat naive algorithm (simply factors the
        characteristic polynomial and computes kernels directly over
        the extension field).  TODO: Maybe implement the better
        algorithm that is in dual_eigenvector in sage/modular/hecke/module.py.

        EXAMPLES:
        We compute the eigenspaces of a $3\times 3$ rational matrix.
            sage: A = matrix(QQ,3,3,range(9)); A
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: es = A.eigenspaces(); es
            [
            (0, Vector space of degree 3 and dimension 1 over Rational Field
            User basis matrix:
            [ 1 -2  1]),
            (a1, Vector space of degree 3 and dimension 1 over Number Field in a1 with defining polynomial x^2 - 12*x - 18
            User basis matrix:
            [            1 1/15*a1 + 2/5 2/15*a1 - 1/5])
            ]
            sage: e, v = es[0]; v = v.basis()[0]
            sage: delta = e*v - v*A
            sage: abs(abs(delta)) < 1e-10
            True

        The same computation, but with implicit base change to a field:
            sage: A = matrix(ZZ,3,range(9)); A
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: A.eigenspaces()
            [
            (0, Vector space of degree 3 and dimension 1 over Rational Field
            User basis matrix:
            [ 1 -2  1]),
            (a1, Vector space of degree 3 and dimension 1 over Number Field in a1 with defining polynomial x^2 - 12*x - 18
            User basis matrix:
            [            1 1/15*a1 + 2/5 2/15*a1 - 1/5])
            ]

        We compute the eigenspaces of the matrix of the Hecke operator
        $T_2$ on level 43 modular symbols. 
            sage: A = ModularSymbols(43).T(2).matrix(); A
            [ 3  0  0  0  0  0 -1]
            [ 0 -2  1  0  0  0  0]
            [ 0 -1  1  1  0 -1  0]
            [ 0 -1  0 -1  2 -1  1]
            [ 0 -1  0  1  1 -1  1]
            [ 0  0 -2  0  2 -2  1]
            [ 0  0 -1  0  1  0 -1]
            sage: A.base_ring()
            Rational Field
            sage: f = A.charpoly(); f
            x^7 + x^6 - 12*x^5 - 16*x^4 + 36*x^3 + 52*x^2 - 32*x - 48
            sage: factor(f)
            (x - 3) * (x + 2)^2 * (x^2 - 2)^2
            sage: A.eigenspaces()
            [
            (3, Vector space of degree 7 and dimension 1 over Rational Field
            User basis matrix:
            [   1    0  1/7    0 -1/7    0 -2/7]),
            (-2, Vector space of degree 7 and dimension 2 over Rational Field
            User basis matrix:
            [ 0  1  0  1 -1  1 -1]
            [ 0  0  1  0 -1  2 -1]),
            (a2, Vector space of degree 7 and dimension 2 over Number Field in a2 with defining polynomial x^2 - 2
            User basis matrix:
            [      0       1       0      -1 -a2 - 1       1      -1]
            [      0       0       1       0      -1       0 -a2 + 1])
            ]

        Next we compute the eigenspaces over the finite field
        of order 11:
            sage: A = ModularSymbols(43, base_ring=GF(11), sign=1).T(2).matrix(); A
            [ 3  9  0  0]
            [ 0  9  0  1]
            [ 0 10  9  2]
            [ 0  9  0  2]
            sage: A.base_ring()
            Finite Field of size 11
            sage: A.charpoly()
            x^4 + 10*x^3 + 3*x^2 + 2*x + 1
            sage: A.eigenspaces(var = 'beta')
            [
            (9, Vector space of degree 4 and dimension 1 over Finite Field of size 11
            User basis matrix:
            [0 0 1 5]),
            (3, Vector space of degree 4 and dimension 1 over Finite Field of size 11
            User basis matrix:
            [1 6 0 6]),
            (beta2, Vector space of degree 4 and dimension 1 over Univariate Quotient Polynomial Ring in beta2 over Finite Field of size 11 with modulus x^2 + 9
            User basis matrix:
            [           0            1            0 5*beta2 + 10])
            ]
    
        TESTS:
           sage: R=RealField(30)
           sage: M=matrix(R,2,[2,1,1,1])
           sage: M.eigenspaces()
           Traceback (most recent call last):
           ...
           NotImplementedError: won't use generic algorithm for inexact base rings, pass the option even_if_inexact=True if you really want this.

           sage: R=ComplexField(30)
           sage: N=matrix(R,2,[2,1,1,1])
           sage: N.eigenspaces()
           Traceback (most recent call last):
           ...
           NotImplementedError: won't use generic algorithm for inexact base rings, pass the option even_if_inexact=True if you really want this.

        But you can ask for (and receive!) garbage: 
            sage: M.eigenspaces(even_if_inexact=True) #random
            [
            (2.6180340, Vector space of degree 2 and dimension 0 over Real Field with 30 bits of precision
            User basis matrix:
            []),
            (0.38196601, Vector space of degree 2 and dimension 0 over Real Field with 30 bits of precision
            User basis matrix:
            [])
            ]

            sage: N.eigenspaces(even_if_inexact=True) #random
            [
            (2.6180340, Vector space of degree 2 and dimension 0 over Complex Field with 30 bits of precision
            User basis matrix:
            []),
            (0.38196601, Vector space of degree 2 and dimension 0 over Complex Field with 30 bits of precision
            User basis matrix:
            [])
            ]


        """
        x = self.fetch('eigenspaces')
        if not x is None:
            return x

        if not self.base_ring().is_exact() and not even_if_inexact:
            raise NotImplementedError, "won't use generic algorithm for inexact base rings, pass the option even_if_inexact=True if you really want this."

        # minpoly is rarely implemented and is unreliable (leading to hangs) via linbox when implemented
        # as of 2007-03-25.
        #try:
        #    G = self.minpoly().factor()  # can be computed faster when available. 
        #except NotImplementedError:
        G = self.fcp()   # factored charpoly of self. 
        V = []
        i = 0
        for h, e in G:
            if h.degree() == 1:
                alpha = -h[0]/h[1]
                F = alpha.parent()
                if F != self.base_ring():
                    self = self.change_ring(F)
                A = self - alpha
            else:
                F = h.root_field('%s%s'%(var,i))
                alpha = F.gen(0)
                A = self.change_ring(F) - alpha
            W = A.kernel()
            i = i + 1
            V.append((alpha, W.ambient_module().span_of_basis(W.basis())))
        V = Sequence(V, cr=True)
        self.cache('eigenspaces', V)
        return V


    #####################################################################################
    # Generic Echelon Form
    ###################################################################################

    def _echelonize_ring(self, **kwds):
        r"""
        Echelonize self in place, where the base ring of self is assumed
        to be a ring (not a field).

        Right now this *only* works over ZZ; otherwise a
        \code{NotImplementedError} is raised.  In the special case of sparse
        matrices over ZZ it makes them dense, gets the echelon form of
        the dense matrix, then sets self equal to the result.

        EXAMPLES:
            sage: a = matrix(ZZ, 3, 4, [1..12], sparse=True); a
            [ 1  2  3  4]
            [ 5  6  7  8]
            [ 9 10 11 12]
            sage: a._echelonize_ring()
            sage: a
            [ 1  2  3  4]
            [ 0  4  8 12]
            [ 0  0  0  0]
        
        """
        self.check_mutability()
        cdef Matrix d
        cdef Py_ssize_t r, c
        if self._base_ring == ZZ:
            if kwds.has_key('include_zero_rows') and not kwds['include_zero_rows']:
                raise ValueError, "cannot echelonize in place and delete zero rows"
            d = self.dense_matrix().echelon_form(**kwds)
            for c from 0 <= c < self.ncols():
                for r from 0 <= r < self.nrows():
                    self.set_unsafe(r, c, d.get_unsafe(r,c))
            self.clear_cache()
            self.cache('pivots', d.pivots())
            self.cache('in_echelon_form', True)
            return 
        else:
            raise NotImplementedError, "echelon form over %s not yet implemented"%self.base_ring()

    def echelonize(self, algorithm="default", cutoff=0, **kwds):
        r"""
        Transform self into a matrix in echelon form over the same
        base ring as self.

        INPUT:
            algorithm -- string, which algorithm to use (default: 'default')
                   'default' -- use a default algorithm, chosen by SAGE
                   'strassen' -- use a Strassen divide and conquer algorithm (if available)
            cutoff -- integer; only used if the Strassen algorithm is selected.

       EXAMPLES:
            sage: a = matrix(QQ,3,range(9)); a
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: a.echelonize()
            sage: a
            [ 1  0 -1]
            [ 0  1  2]
            [ 0  0  0]         

        An immutable matrix cannot be transformed into echelon form.
        Use \code{self.echelon_form()} instead:
        
            sage: a = matrix(QQ,3,range(9)); a.set_immutable()
            sage: a.echelonize()
            Traceback (most recent call last):
            ...
            ValueError: matrix is immutable; please change a copy instead (use self.copy()).
            sage: a.echelon_form()
            [ 1  0 -1]
            [ 0  1  2]
            [ 0  0  0]            

        Echelon form over the integers is what is also classically often known as
        Hermite normal form:
            sage: a = matrix(ZZ,3,range(9))
            sage: a.echelonize(); a
            [ 3  0 -3]
            [ 0  1  2]
            [ 0  0  0]

        We compute an echelon form both over a domain and fraction field:
        
            sage: R.<x,y> = QQ[]
            sage: a = matrix(R, 2, [x,y,x,y])
            sage: a.echelon_form()               # not very useful? -- why two copies of the same row?
            [x y]
            [x y]

            sage: b = a.change_ring(R.fraction_field()) 
            sage: b.echelon_form()               # potentially useful
            [  1 y/x]
            [  0   0]

        Echelon form is not defined over arbitrary rings:
            sage: a = matrix(Integers(9),3,range(9))
            sage: a.echelon_form()
            Traceback (most recent call last):
            ...
            NotImplementedError: Echelon form not implemented over 'Ring of integers modulo 9'.

        Involving a sparse matrix:
            sage: m = matrix(3,[1, 1, 1, 1, 0, 2, 1, 2, 0], sparse=True); m
            [1 1 1]
            [1 0 2]
            [1 2 0]
            sage: m.echelon_form()
            [ 1  0  2]
            [ 0  1 -1]
            [ 0  0  0]            
            sage: m.echelonize(); m
            [ 1  0  2]
            [ 0  1 -1]
            [ 0  0  0]
        """
        self.check_mutability()

        if algorithm == 'default':
            if self._will_use_strassen_echelon():
                algorithm = 'strassen'
            else:
                algorithm = 'classical'
        try:
            if self.base_ring().is_field():
                if algorithm == 'classical':
                    self._echelon_in_place_classical()
                elif algorithm == 'strassen':
                    self._echelon_strassen(cutoff)
                else:
                    raise ValueError, "Unknown algorithm '%s'"%algorithm
            else:
                if not (algorithm in ['classical', 'strassen']):
                    kwds['algorithm'] = algorithm
                self._echelonize_ring(**kwds)
        except ArithmeticError, msg:
            raise NotImplementedError, "Echelon form not implemented over '%s'."%self.base_ring()

    def echelon_form(self, algorithm="default", cutoff=0, **kwds):
        """
        Return the echelon form of self.

        INPUT:
            matrix -- an element A of a MatrixSpace

        OUTPUT:
            matrix -- The reduced row echelon form of A, as an
            immutable matrix.  Note that self is *not* changed by this
            command.  Use A.echelonize() to change A in place.

        EXAMPLES:
           sage: MS = MatrixSpace(GF(19),2,3)
           sage: C = MS.matrix([1,2,3,4,5,6])
           sage: C.rank()
           2
           sage: C.nullity()
           0
           sage: C.echelon_form()
           [ 1  0 18]
           [ 0  1  2]
        """
        x = self.fetch('echelon_form')
        if not x is None:
            return x
        E = self.copy()
        if algorithm == 'default':
            E.echelonize(cutoff=cutoff)
        else:
            E.echelonize(algorithm = algorithm, cutoff=cutoff)
        E.set_immutable()  # so we can cache the echelon form. 
        self.cache('echelon_form', E)
        self.cache('pivots', E.pivots())
        return E
        
    def _echelon_classical(self):
        """
        Return the echelon form of self.
        """
        E = self.fetch('echelon_classical')
        if not E is None:
            return E
        E = self.copy()
        E._echelon_in_place_classical()
        self.cache('echelon_classical', E)
        return E

    def _echelon_in_place_classical(self):
        """
        Return the echelon form of self and set the pivots of self.

        EXAMPLES:
            sage: t = matrix(QQ, 3, range(9)); t
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: t._echelon_in_place_classical(); t
            [ 1  0 -1]
            [ 0  1  2]
            [ 0  0  0]
        """
        tm = verbose('generic in-place Gauss elimination on %s x %s matrix'%(self._nrows, self._ncols))
        cdef Py_ssize_t start_row, c, r, nr, nc, i
        if self.fetch('in_echelon_form'):
            return

        self.check_mutability()
        cdef Matrix A, d

        nr = self._nrows
        nc = self._ncols
        A = self
        
        start_row = 0
        pivots = []

        for c from 0 <= c < nc:
            if PyErr_CheckSignals(): raise KeyboardInterrupt
            for r from start_row <= r < nr:
                if A.get_unsafe(r, c):
                    pivots.append(c)
                    a_inverse = ~A.get_unsafe(r,c)
                    A.rescale_row(r, a_inverse, c)
                    A.swap_rows(r, start_row)
                    for i from 0 <= i < nr:
                        if i != start_row:
                            if A.get_unsafe(i,c):
                                minus_b = -A.get_unsafe(i, c)
                                A.add_multiple_of_row(i, start_row, minus_b, c)
                    start_row = start_row + 1
                    break
        self.cache('pivots', pivots)
        A.cache('pivots', pivots)
        A.cache('in_echelon_form', True)
        self.cache('echelon_form', A)

        verbose('done with gauss echelon form', tm)

    #####################################################################################
    # Windowed Strassen Matrix Multiplication and Echelon
    # Precise algorithms invented and implemented by David Harvey and Robert Bradshaw
    # at William Stein's MSRI 2006 Summer Workshop on Modular Forms. 
    #####################################################################################
    def _multiply_strassen(self, Matrix right, int cutoff=0):
        """
        Multiply self by the matrix right using a Strassen-based
        asymptotically fast arithmetic algorithm.

        ALGORITHM: Custom algorithm for arbitrary size matrices
        designed by David Harvey and Robert Bradshaw, based on
        Strassen's algorithm.

        INPUT:
            cutoff -- integer (default: 0 -- let class decide).

        EXAMPLES:
            sage: a = matrix(ZZ,4,range(16))
            sage: a._multiply_strassen(a,2)
            [ 56  62  68  74]
            [152 174 196 218]
            [248 286 324 362]
            [344 398 452 506]
        """
        if self._ncols != right._nrows:
            raise ArithmeticError, "Number of columns of self must equal number of rows of right."
        if not self._base_ring is right.base_ring():
            raise TypeError, "Base rings must be the same."

        if cutoff == 0:
            cutoff = self._strassen_default_cutoff(right)

        if cutoff <= 0:
            raise ValueError, "cutoff must be at least 1"

        output = self.new_matrix(self._nrows, right._ncols)
        
        self_window   = self.matrix_window()
        right_window  = right.matrix_window()
        output_window = output.matrix_window()


        import strassen
        strassen.strassen_window_multiply(output_window, self_window, right_window, cutoff)
        return output

    def _echelon_strassen(self, int cutoff=0):
        """
        In place Strassen echelon of self, and sets the pivots.

        ALGORITHM: Custom algorithm for arbitrary size matrices
        designed by David Harvey and Robert Bradshaw, based on
        Strassen's algorithm.

        EXAMPLES:
            sage: A = matrix(QQ, 4, range(16))
            sage: A._echelon_strassen(2)
            sage: A
            [ 1  0 -1 -2]
            [ 0  1  2  3]
            [ 0  0  0  0]
            [ 0  0  0  0]
        """
        tm = verbose('strassen echelon of %s x %s matrix'%(self._nrows, self._ncols))
        
        self.check_mutability()

        if not self._base_ring.is_field():
            raise ValueError, "Echelon form not defined over this base ring."

        if cutoff == 0:
            cutoff = self._strassen_default_echelon_cutoff()

        if cutoff < 1:
            raise ValueError, "cutoff must be at least 1"

        if self._nrows < cutoff or self._ncols < cutoff:
            self._echelon_in_place_classical()
            return
        
        import strassen            
        pivots = strassen.strassen_echelon(self.matrix_window(), cutoff)
        self._set_pivots(pivots)
        verbose('done with strassen', tm)

    def matrix_window(self, Py_ssize_t row=0, Py_ssize_t col=0,
                      Py_ssize_t nrows=-1, Py_ssize_t ncols=-1):
        """
        Return the requested matrix window.

        EXAMPLES:
            sage: A = matrix(QQ, 3, range(9))
            sage: A.matrix_window(1,1, 2, 1)
            Matrix window of size 2 x 1 at (1,1):
            [0 1 2]
            [3 4 5]
            [6 7 8]
        """
        return self.matrix_window_c(row, col, nrows, ncols)
    
    cdef matrix_window_c(self, Py_ssize_t row, Py_ssize_t col,
                         Py_ssize_t nrows, Py_ssize_t ncols):
        import matrix_window
        if nrows == -1:
            nrows = self._nrows - row
        if ncols == -1:
            ncols = self._ncols - col
        return matrix_window.MatrixWindow(self, row, col, nrows, ncols)
        
    def set_block(self, row, col, block):
        """
        Sets the sub-matrix of self, with upper left corner given by row, col
        to block. 
        
        EXAMPLES: 
            sage: A = matrix(QQ, 3, 3, range(9))/2
            sage: B = matrix(ZZ, 2, 1, [100,200])
            sage: A.set_block(0, 1, B)
            sage: A
            [  0 100   1]
            [3/2 200 5/2]
            [  3 7/2   4]            
        """
        self.check_mutability()
        if block.base_ring() is not self.base_ring():
            block = block.change_ring(self.base_ring())
        window = self.matrix_window(row, col, block.nrows(), block.ncols())
        window.set(block.matrix_window())
        
    def subdivide(self, row_lines=None, col_lines=None):
        """
        Divides self into logical submatrices which can then be 
        queried and extracted. If a subdivision already exists, 
        this method forgets the previous subdivision and flushes
        the cache. 
        
        INPUT: 
            row_lines -- None, an integer, or a list of integers
            col_lines -- None, an integer, or a list of integers
            
        OUTPUT: 
            changes self
            
        NOTE: 
            One may also pass a tuple into the first argument which will 
            be interpreted as (row_lines, col_lines)
        
        EXAMPLES:
            sage: M = matrix(5, 5, prime_range(100))
            sage: M.subdivide(2,3); M
            [ 2  3  5| 7 11]
            [13 17 19|23 29]
            [--------+-----]
            [31 37 41|43 47]
            [53 59 61|67 71]
            [73 79 83|89 97]
            sage: M.subdivision(0,0)
            [ 2  3  5]
            [13 17 19]
            sage: M.subdivision(1,0)
            [31 37 41]
            [53 59 61]
            [73 79 83]
            sage: M.subdivision_entry(1,0,0,0)
            31
            sage: M.get_subdivisions()
            ([2], [3])
            sage: M.subdivide(None, [1,3]); M
            [ 2| 3  5| 7 11]
            [13|17 19|23 29]
            [31|37 41|43 47]
            [53|59 61|67 71]
            [73|79 83|89 97]
            
        Degenerate cases work too. 
            sage: M.subdivide([2,5], [0,1,3]); M
            [| 2| 3  5| 7 11]
            [|13|17 19|23 29]
            [+--+-----+-----]
            [|31|37 41|43 47]
            [|53|59 61|67 71]
            [|73|79 83|89 97]
            [+--+-----+-----]
            sage: M.subdivision(0,0)
            []
            sage: M.subdivision(0,1)
            [ 2]
            [13]
            sage: M.subdivide([2,2,3], [0,0,1,1]); M
            [|| 2|| 3  5  7 11]
            [||13||17 19 23 29]
            [++--++-----------]
            [++--++-----------]
            [||31||37 41 43 47]
            [++--++-----------]
            [||53||59 61 67 71]
            [||73||79 83 89 97]
            sage: M.subdivision(0,0)
            []
            sage: M.subdivision(2,4)
            [37 41 43 47]
            
        AUTHOR: 
            -- Robert Bradshaw (2007-06-14)
        """
        
        self.check_mutability()
        if col_lines is None and row_lines is not None and isinstance(row_lines, tuple):
            tmp = row_lines
            row_lines, col_lines = tmp
        if row_lines is None:
            row_lines = []
        elif not isinstance(row_lines, list):
            row_lines = [row_lines]
        if col_lines is None:
            col_lines = []
        elif not isinstance(col_lines, list):
            col_lines = [col_lines]
        row_lines = [0] + [int(ZZ(x)) for x in row_lines] + [self._nrows]
        col_lines = [0] + [int(ZZ(x)) for x in col_lines] + [self._ncols]
        if self.subdivisions is not None:
            self.clear_cache()
        self.subdivisions = (row_lines, col_lines)
        
    def subdivision(self, i, j):
        """
        Returns in immutable copy of the (i,j)th submatrix of self, 
        according to a previously set subdivision. 
        
        Before a subdivision is set, the only valid arguments are 
        (0,0) which returns self. 
        
        EXAMPLE: 
            sage: M = matrix(3, 4, range(12))
            sage: M.subdivide(1,2); M
            [ 0  1| 2  3]
            [-----+-----]
            [ 4  5| 6  7]
            [ 8  9|10 11]
            sage: M.subdivision(0,0)
            [0 1]
            sage: M.subdivision(0,1)
            [2 3]
            sage: M.subdivision(1,0)
            [4 5]
            [8 9]
            
        It handles size-zero subdivisions as well. 
            sage: M = matrix(3, 4, range(12))
            sage: M.subdivide([0],[0,2,2,4]); M
            [+-----++-----+]
            [| 0  1|| 2  3|]
            [| 4  5|| 6  7|]
            [| 8  9||10 11|]
            sage: M.subdivision(0,0)
            []
            sage: M.subdivision(1,1)
            [0 1]
            [4 5]
            [8 9]
            sage: M.subdivision(1,2)
            []
            sage: M.subdivision(1,0)
            []
            sage: M.subdivision(0,1)
            []
        """
        if self.subdivisions is None:
            self.subdivisions = ([0, self._nrows], [0, self._ncols])
        key = "subdivision %s %s"%(i,j)
        sd = self.fetch(key)
        if sd is None:
            sd = self.submatrix(self.subdivisions[0][i], self.subdivisions[1][j], 
                                self.subdivisions[0][i+1]-self.subdivisions[0][i], self.subdivisions[1][j+1]-self.subdivisions[1][j])
            sd.set_immutable()
            self.cache(key, sd)
        return sd
        
    def subdivision_entry(self, i, j, x, y):
        """
        Returns the x,y entry of the i,j submatrix of self. 
        
        EXAMPLES: 
            sage: M = matrix(5, 5, range(25))
            sage: M.subdivide(3,3); M
            [ 0  1  2| 3  4]
            [ 5  6  7| 8  9]
            [10 11 12|13 14]
            [--------+-----]
            [15 16 17|18 19]
            [20 21 22|23 24]
            sage: M.subdivision_entry(0,0,1,2)
            7
            sage: M.subdivision(0,0)[1,2]
            7
            sage: M.subdivision_entry(0,1,0,0)
            3
            sage: M.subdivision_entry(1,0,0,0)
            15
            sage: M.subdivision_entry(1,1,1,1)
            24
            
        Even though this entry exists in the matrix, the index is invalid for the submatrix. 
            sage: M.subdivision_entry(0,0,4,0)
            Traceback (most recent call last):
            ...
            IndexError: Submatrix 0,0 has no entry 4,0
        """
        if self.subdivisions is None:
            if not i and not j:
                return self[x,y]
            else:
                raise IndexError, "No such submatrix %s, %s"%(i,j)
        if x >= self.subdivisions[0][i+1]-self.subdivisions[0][i] or \
           y >= self.subdivisions[1][j+1]-self.subdivisions[1][j]:
            raise IndexError, "Submatrix %s,%s has no entry %s,%s"%(i,j, x, y)
        return self[self.subdivisions[0][i] + x , self.subdivisions[1][j] + y]

    def get_subdivisions(self):
        """
        Returns the current subdivision of self. 
        
        EXAMPLES: 
            sage: M = matrix(5, 5, range(25))
            sage: M.get_subdivisions()
            ([], [])
            sage: M.subdivide(2,3)
            sage: M.get_subdivisions()
            ([2], [3])
            sage: N = M.parent()(1)
            sage: N.subdivide(M.get_subdivisions()); N
            [1 0 0|0 0]
            [0 1 0|0 0]
            [-----+---]
            [0 0 1|0 0]
            [0 0 0|1 0]
            [0 0 0|0 1]
        """
        if self.subdivisions is None:
            return ([], [])
        else:
            return (self.subdivisions[0][1:-1], self.subdivisions[1][1:-1])
            
    def tensor_product(self,Y):
        """
        Returns the tensor product of two matrices.

        EXAMPLES:
            sage: M1=Matrix(QQ,[[-1,0],[-1/2,-1]])
            sage: M2=Matrix(ZZ,[[1,-1,2],[-2,4,8]])
            sage: M1.tensor_product(M2)
            [  -1    1   -2|   0    0    0]
            [   2   -4   -8|   0    0    0]
            [--------------+--------------]
            [-1/2  1/2   -1|  -1    1   -2]
            [   1   -2   -4|   2   -4   -8]
            sage: M2.tensor_product(M1)
            [  -1    0|   1    0|  -2    0]
            [-1/2   -1| 1/2    1|  -1   -2]
            [---------+---------+---------]
            [   2    0|  -4    0|  -8    0]
            [   1    2|  -2   -4|  -4   -8]
        """
        if not isinstance(Y,Matrix):
            raise TypeError, "second argument must be a matrix"
        return sage.matrix.constructor.block_matrix([x*Y for x in self.list()],self.nrows(),self.ncols())

    def randomize(self, density=1, *args, **kwds):
        """
        Randomize density proportion of the entries of this matrix,
        leaving the rest unchanged.

        NOTE: We actually choose at random density proportion of
        entries of the matrix and set them to random elements.  It's
        possible that the same position can be chosen multiple times,
        especially for a very small matrix.

        INPUT:
            density -- integer (default: 1) rough measure of the
                       proportion of nonzero entries in the random
                       matrix
            *args, **kwds -- rest of parameters may be passed to the
                       random_element function of the base ring.

        EXAMPLES:
        We construct the zero matrix over a polynomial ring.
            sage: a = matrix(QQ['x'], 3); a
            [0 0 0]
            [0 0 0]
            [0 0 0]

        We then randomize roughly half the entries:
            sage: a.randomize(0.5)
            sage: a
            [      1/2*x^2 - x - 12 1/2*x^2 - 1/95*x - 1/2                      0]
            [-5/2*x^2 + 2/3*x - 1/4                      0                      0]
            [          -x^2 + 2/3*x                      0                      0]

        Now we randomize all the entries of the resulting matrix:
            sage: a.randomize()
            sage: a
            [     1/3*x^2 - x + 1             -x^2 + 1              x^2 - x]
            [ -1/14*x^2 - x - 1/4           -4*x - 1/5 -1/4*x^2 - 1/2*x + 4]
            [ 1/9*x^2 + 5/2*x - 3     -x^2 + 3/2*x + 1   -2/7*x^2 - x - 1/2]

        We create the zero matrix over the integers:
            sage: a = matrix(ZZ, 2); a
            [0 0]
            [0 0]

        Then we randomize it; the x and y parameters, which determine
        the size of the random elements, are passed onto the ZZ
        random_element method.
            sage: a.randomize(x=-2^64, y=2^64)
            sage: a
            [-12401200298100116246   1709403521783430739]
            [ -4417091203680573707  17094769731745295000]
        """
        randint = current_randstate().python_random().randint

        density = float(density)
        if density == 0:
            return 
        self.check_mutability()
        self.clear_cache()
        
        R = self.base_ring()

        cdef Py_ssize_t i, j, num

        if density >= 1:
            for i from 0 <= i < self._nrows:
                for j from 0 <= j < self._ncols:
                    self.set_unsafe(i, j, R.random_element(*args, **kwds))
        else:
            num = int(self._nrows * self._ncols * density)
            for i from 0 <= i < num:
                self.set_unsafe(randint(0, self._nrows - 1),
                                randint(0, self._ncols - 1),
                                R.random_element(*args, **kwds))

    def is_one(self):
        """
        Return True if this matrix is the identity matrix.

        EXAMPLES:
            sage: m = matrix(QQ,2,range(4))
            sage: m.is_one()
            False
            sage: m = matrix(QQ,2,[5,0,0,5])
            sage: m.is_one()
            False
            sage: m = matrix(QQ,2,[1,0,0,1])
            sage: m.is_one()
            True
            sage: m = matrix(QQ,2,[1,1,1,1])
            sage: m.is_one()
            False
        """
        return self.is_scalar(1)

    def is_scalar(self, a = None):
        """
        Return True if this matrix is a scalar matrix.

        INPUT -- base_ring element a, which is chosen as self[0][0] if
                 a = None

        OUTPUT -- whether self is a scalar matrix (in fact the scalar
                  matrix aI if a is input)

        EXAMPLES:
            sage: m = matrix(QQ,2,range(4))
            sage: m.is_scalar(5)
            False
            sage: m = matrix(QQ,2,[5,0,0,5])
            sage: m.is_scalar(5)
            True
            sage: m = matrix(QQ,2,[1,0,0,1])
            sage: m.is_scalar(1)
            True
            sage: m = matrix(QQ,2,[1,1,1,1])
            sage: m.is_scalar(1)
            False
        """
        if not self.is_square():
            return False
        cdef Py_ssize_t i, j
        if a is None:
            if self._nrows == 0:
                return True
            a = self.get_unsafe(0,0)
        else:
            a = self.base_ring()(a)
        zero = self.base_ring()(0)
        for i from 0 <= i < self._nrows:
            for j from 0 <= j < self._ncols:
                if i != j:
                    if self.get_unsafe(i,j) != zero:
                        return False
                else:
                    if self.get_unsafe(i, i) != a:
                        return False
        return True

    def visualize_structure(self, filename=None, maxsize=512):
        """
        Write a PNG image to 'filename' which visualizes self by putting
        black pixels in those positions which have nonzero entries.

        White pixels are put at positions with zero entries. If 'maxsize'
        is given, then the maximal dimension in either x or y direction is
        set to 'maxsize' depending on which is bigger. If the image is
        scaled, the darkness of the pixel reflects how many of the
        represented entries are nonzero. So if e.g. one image pixel
        actually represents a 2x2 submatrix, the dot is darker the more of
        the four values are nonzero.

        INPUT:
            filename -- either a path or None in which case a filename in
                        the current directory is chosen automatically
                        (default:None)

            maxsize -- maximal dimension in either x or y direction of the resulting
                       image. If None or a maxsize larger than
                       max(self.nrows(),self.ncols()) is given the image will have
                       the same pixelsize as the matrix dimensions (default: 512)

        EXAMPLE:
            sage: M = random_matrix(CC, 4)
            sage: M.visualize_structure()           # not tested

        WARNING -- the above *may* fail on some OSX systems due to some libpng.dylib issues.
        """
        import gd
        import os
        
        cdef int x, y, _x, _y, v, bi, bisq
        cdef int ir,ic
        cdef float b, fct

        mr, mc = self.nrows(), self.ncols()

        if maxsize is None:

            ir = mc
            ic = mr
            b = 1.0

        elif max(mr,mc) > maxsize:

            maxsize = float(maxsize)
            ir = int(mc * maxsize/max(mr,mc))
            ic = int(mr * maxsize/max(mr,mc))
            b = max(mr,mc)/maxsize

        else:

            ir = mc
            ic = mr
            b = 1.0
            
        fct = 255.0/(b*b)
        bi = <int>b
        bisq = bi*bi

        im = gd.image((ir,ic),1)
        white = im.colorExact((255,255,255))
        im.fill((0,0),white)

        # these speed things up a bit 
        colorExact = im.colorExact
        setPixel = im.setPixel

        for x from 0 <= x < ic:
            for y from 0 <= y < ir:
                v = bisq
                for _x from 0 <= _x < bi:
                    for _y from 0 <= _y < bi:
                        if not self.get_unsafe(<int>(x*b + _x), <int>(y*b + _y)).is_zero():
                            v-=1 #increase darkness

                v = int(v*v*fct)
                val = colorExact((v,v,v))
                setPixel((y,x), val)

        if filename is None:
            filename = graphics_filename()

        im.writePng(filename)

    def density(self):
        """
        Return the density of self.

        By density we understand the ration of the number of nonzero
        positions and the self.nrows() * self.ncols(), i.e. the number
        of possible nonzero positions.

        EXAMPLE:
        
            First, note that the density parameter does not ensure
            the density of a matrix, it is only an upper bound.

            sage: A = random_matrix(GF(127),200,200,density=0.3)
            sage: A.density()
            5159/20000

            sage: A = matrix(QQ,3,3,[0,1,2,3,0,0,6,7,8])
            sage: A.density()
            2/3
        
        """
        cdef int x,y,k
        k = 0
        nr = self.nrows()
        nc = self.ncols()
        for x from 0 <= x < nr:
            for y from 0 <= y < nc:
                if not self.get_unsafe(x,y).is_zero():
                    k+=1
        return QQ(k)/QQ(nr*nc)


    def inverse(self):
        """
        Returns the inverse of self, without changing self.

        Note that one can use the Python inverse operator ~
        to obtain the inverse as well.

        EXAMPLES:
            sage: m = matrix([[1,2],[3,4]])
            sage: m^(-1)
            [  -2    1]
            [ 3/2 -1/2]
            sage: m.inverse()
            [  -2    1]
            [ 3/2 -1/2]
            sage: ~m
            [  -2    1]
            [ 3/2 -1/2]           

            sage: m = matrix([[1,2],[3,4]], sparse=True)
            sage: m^(-1)
            [  -2    1]
            [ 3/2 -1/2]
            sage: m.inverse()
            [  -2    1]
            [ 3/2 -1/2]
            sage: ~m
            [  -2    1]
            [ 3/2 -1/2]           
 
        """
        return self.__invert__()

    def gram_schmidt(self):
        r"""
        Return the matrix G whose rows are obtained from the rows of self (=A) by
        applying the Gram-Schmidt orthogonalization process.  Also return
        the coefficients mu ij, i.e., a matrix mu such that \code{(mu + 1)*G == A}.

        OUTPUT:
            G -- a matrix whose rows are orthogonal
            mu -- a matrix that gives the transformation, via the relation
                  (mu + 1)*G == self
        
        EXAMPLES:
            sage: A = matrix(ZZ, 3, [-1, 2, 5, -11, 1, 1, 1, -1, -3]); A
            [ -1   2   5]
            [-11   1   1]
            [  1  -1  -3]
            sage: G, mu = A.gram_schmidt()
            sage: G
            [     -1       2       5]
            [  -52/5    -1/5      -2]
            [  2/187  36/187 -14/187]
            sage: mu
            [     0      0      0]
            [   3/5      0      0]
            [  -3/5 -7/187      0]
            sage: G.row(0) * G.row(1)
            0
            sage: G.row(0) * G.row(2)
            0
            sage: G.row(1) * G.row(2)
            0

        The relation between mu and A is as follows:
            sage: (mu + 1)*G == A
            True
        """        
        from sage.modules.misc import gram_schmidt
        from constructor import matrix
        Bstar, mu = gram_schmidt(self.rows())
        return matrix(Bstar), mu

    def jordan_form(self, base_ring=None, sparse=False, subdivide=True):
        r"""
        Compute the Jordan canonical form of the matrix, if it exists.

	This computation is performed in a naive way using the ranks
        of powers of A-xI, where x is an eigenvalue of the matrix A.

        INPUT:
            base_ring -- ring in which to compute the Jordan form.
            sparse -- (default False) If sparse=True, return a sparse matrix.
            subdivide -- (default True) If subdivide=True, the subdivisions
                         for the Jordan blocks in the matrix are shown.

        EXAMPLES:
            sage: a = matrix(ZZ,4,[1, 0, 0, 0, 0, 1, 0, 0, 1, \
            -1, 1, 0, 1, -1, 1, 2]); a
            [ 1  0  0  0]
            [ 0  1  0  0]
            [ 1 -1  1  0]
            [ 1 -1  1  2]
            sage: a.jordan_form()
            [2|0 0|0]
            [-+---+-]
            [0|1 1|0]
            [0|0 1|0]
            [-+---+-]
            [0|0 0|1]
            sage: a.jordan_form(subdivide=False)
            [2 0 0 0]
            [0 1 1 0]
            [0 0 1 0] 
            [0 0 0 1]
            sage: b = matrix(ZZ,3,range(9)); b
            [0 1 2]
            [3 4 5]
            [6 7 8]
            sage: b.jordan_form()             
            Traceback (most recent call last):
            ...
            RuntimeError: Some eigenvalue does not exist in Integer Ring.
            sage: b.jordan_form(RealField(15))
            [-1.348|0.0000|0.0000]
            [------+------+------]
            [0.0000|0.0000|0.0000]
            [------+------+------]
            [0.0000|0.0000| 13.35]

        """
        from sage.matrix.constructor import block_diagonal_matrix, jordan_block, diagonal_matrix
        from sage.combinat.partition import Partition

        size=self.nrows()

        if base_ring is None:
            mat = self
        else:
            mat = self.change_ring(base_ring)
            
        evals=mat.charpoly().roots()
        if sum([mult for (_,mult) in evals]) < size:
            raise RuntimeError("Some eigenvalue does not exist in %s."%(mat.base_ring()))
        blocks=[]
        for (eval, mult) in evals:
            if mult == 1:
                blocks.append((eval,1))
            else:
                b=mat - diagonal_matrix([eval]*size, sparse=sparse)
                c=b
                ranks=[mat.rank(), c.rank()]
                i=0
                while (ranks[i]-ranks[i+1]>0) and ranks[i+1] > size-mult:
                    c=b*c
                    ranks.append(c.rank())
                    i=i+1
                diagram = [ranks[i]-ranks[i+1] for i in xrange(len(ranks)-1)]
                blocks.extend([(eval,i) for i in Partition(diagram).conjugate()])
        return block_diagonal_matrix([jordan_block(eval,size, sparse=sparse) for (eval,size) in blocks],subdivide=subdivide)

    def symplectic_form(self):
        r"""
        Find a symplectic form for self if self is an anti-symmetric,
        alternating matrix defined over a field.

        Returns a pair (F, C) such that the rows of C form a symplectic
        basis for self and F = C * self * C.transpose().

        Raises a ValueError if not over a field, or self is not
        anti-symmetric, or self is not alternating.

        Anti-symmetric means that $M = -M^t$.  Alternating means that the
        diagonal of $M$ is identically zero.

        A symplectic basis is a basis of the form $z_1, \ldots, z_i, e_1,
        \ldots, e_j, f_1, \ldots f_j$ such that
            * $z_i M v^t$ = 0 for all vectors $v$;
            * $e_i M {e_j}^t = 0$ for all $i, j$;
            * $f_i M {f_j}^t = 0$ for all $i, j$;
            * $e_i M {f_i}^t = 1$ for all $i$;
            * $e_i M {f_j}^t = 0$ for all $i$ not equal $j$.

        See the example for a pictorial description of such a basis.

        EXAMPLES:
            sage: E = matrix(QQ, 8, 8, [0, -1/2, -2, 1/2, 2, 0, -2, 1, 1/2, 0, -1, -3, 0, 2, 5/2, -3, 2, 1, 0, 3/2, -1, 0, -1, -2, -1/2, 3, -3/2, 0, 1, 3/2, -1/2, -1/2, -2, 0, 1, -1, 0, 0, 1, -1, 0, -2, 0, -3/2, 0, 0, 1/2, -2, 2, -5/2, 1, 1/2, -1, -1/2, 0, -1, -1, 3, 2, 1/2, 1, 2, 1, 0]); E
            [   0 -1/2   -2  1/2    2    0   -2    1]
            [ 1/2    0   -1   -3    0    2  5/2   -3]
            [   2    1    0  3/2   -1    0   -1   -2]
            [-1/2    3 -3/2    0    1  3/2 -1/2 -1/2]
            [  -2    0    1   -1    0    0    1   -1]
            [   0   -2    0 -3/2    0    0  1/2   -2]
            [   2 -5/2    1  1/2   -1 -1/2    0   -1]
            [  -1    3    2  1/2    1    2    1    0]
            sage: F, C = E.symplectic_form(); F
            [ 0  0  0  0  1  0  0  0]
            [ 0  0  0  0  0  1  0  0]
            [ 0  0  0  0  0  0  1  0]
            [ 0  0  0  0  0  0  0  1]
            [-1  0  0  0  0  0  0  0]
            [ 0 -1  0  0  0  0  0  0]
            [ 0  0 -1  0  0  0  0  0]
            [ 0  0  0 -1  0  0  0  0]        
            sage: F == C * E * C.transpose()
            True
            """
        import sage.matrix.symplectic_basis
        return sage.matrix.symplectic_basis.symplectic_basis_over_field(self)

    def hadamard_bound(self):
        r"""
        Return an int n such that the absolute value of the
        determinant of this matrix is at most $10^n$.

        This is got using both the row norms and the column norms.

        This function only makes sense when the base field can be
        coerced to the real double field RDF or the MPFR Real Field
        with 53-bits precision.

        EXAMPLES:
            sage: a = matrix(ZZ, 3, [1,2,5,7,-3,4,2,1,123])
            sage: a.hadamard_bound()
            4
            sage: a.det()
            -2014
            sage: 10^4
            10000

        In this example the Hadamard bound has to be computed (automatically)
        using mpfr instead of doubles, since doubles overflow:
            sage: a = matrix(ZZ, 2, [2^10000,3^10000,2^50,3^19292])
            sage: a.hadamard_bound()
            12215
            sage: len(str(a.det()))
            12215
        """
        from sage.rings.all import RDF, RealField
        try:
            A = self.change_ring(RDF)
            m1 = A._hadamard_row_bound()
            A = A.transpose()
            m2 = A._hadamard_row_bound()
            return min(m1, m2)
        except (OverflowError, TypeError):
            # Try using MPFR, which handles large numbers much better, but is slower.
            import misc
            R = RealField(53, rnd='RNDU')
            A = self.change_ring(R)
            m1 = misc.hadamard_row_bound_mpfr(A)
            A = A.transpose()
            m2 = misc.hadamard_row_bound_mpfr(A)
            return min(m1, m2)

            
    
def _dim_cmp(x,y):
    """
    Used internally by matrix functions.  Given 2-tuples (x,y),
    returns their comparision based on the first component.

    EXAMPLES:
        sage: from sage.matrix.matrix2 import _dim_cmp
        sage: V = [(QQ^3, 2), (QQ^2, 1)]
        sage: _dim_cmp(V[0], V[1])
        1    
    """
    return cmp(x[0].dimension(), y[0].dimension())

def decomp_seq(v):
    """
    This function is used internally be the decomposition matrix
    method.  It takes a list of tuples and produces a sequence
    that is correctly sorted and prints with carriage returns.
    
    EXAMPLES:
        sage: from sage.matrix.matrix2 import decomp_seq
        sage: V = [(QQ^3, 2), (QQ^2, 1)]
        sage: decomp_seq(V)
        [
        (Vector space of dimension 2 over Rational Field, 1),
        (Vector space of dimension 3 over Rational Field, 2)
        ]
    """
    list.sort(v, _dim_cmp)
    return Sequence(v, universe=tuple, check=False, cr=True)
    
    
def cmp_pivots(x,y):
    """
    Compare two sequences of pivot columns.
    If x is shorter than y, return -1, i.e., x < y, "not as good".
    If x is longer than y, x > y, "better"
    If the length is the same then x is better, i.e., x > y
        if the entries of x are correspondingly >= those of y with
        one being greater.
    """
    if len(x) < len(y):
        return -1
    if len(x) > len(y):
        return 1
    if x < y:
        return 1
    elif x == y:
        return 0
    else:
        return -1


def _choose(Py_ssize_t n, Py_ssize_t t):
    """
    Returns all possible sublists of length t from range(n)

    Based on algoritm T from Knuth's taocp part 4: 7.2.1.3 p.5
    This function replaces the one based on algorithm L because it is faster.

    EXAMPLES:
        sage: from sage.matrix.matrix2 import _choose
        sage: _choose(1,1)
        [[0]]
        sage: _choose(4,1)
        [[0], [1], [2], [3]]
        sage: _choose(4,4)
        [[0, 1, 2, 3]]

    AUTHOR:
        -- Jaap Spies (2007-11-14)
    """
    cdef Py_ssize_t j, temp

    x = []               # initialize T1
    c = range(t)
    if t == n:
        x.append(c)
        return x
    c.append(n)
    c.append(0)
    j = t-1

    while True:
        x.append(c[:t])    # visit T2
        if j >= 0:
            c[j] = j+1
            j = j-1
            continue       # goto T2

        if c[0]+1 < c[1]:  # T3 easy case!
            c[0] = c[0]+1
            continue
        else:
            j = 1

        while True:
            c[j-1] = j-1      # T4 find j
            temp = c[j]+1
            if temp == c[j+1]:
                j = j+1
            else:
                break


        if j >= t:     # T5 stop?
            break

        c[j] = temp    # T6
        j = j-1

    return x


def _binomial(Py_ssize_t n, Py_ssize_t k):
    """
    Fast and unchecked implementation of binomial(n,k)
    This is only for internal use.

    EXAMPLES:
        sage: from sage.matrix.matrix2 import _binomial
        sage: _binomial(10,2)
        45
        sage: _binomial(10,5)
        252

    AUTHOR:
        -- Jaap Spies (2007-10-26)

    """
    cdef Py_ssize_t i

    if k > (n/2):
        k = n-k
    if k == 0:
        return 1

    result = n
    n, k = n-1, k-1
    i = 2
    while k > 0:
        result = (result*n)/i
        i, n, k = i+1, n-1, k-1
    return result

