import operator
from itertools import imap, combinations
from math import log
from libc.math cimport sqrt
from libc.math cimport log2
import Orange

def datasets_distance(set1, set2, metric_function):
    """
    Measures similarity between two datasets as D1 + D2, where:
    D1 -- sum of distances between each instance from set1 and the nearest
          instance from set2.
    D2 -- sum of distances between each instance from set2 and the nearest
          instance from set1.
    """
    def d(s1,s2):
        return sum(imap(lambda i1: instance_dataset_distance(i1, s2,
                                                    metric_function), s1))
    return d(set1, set2) + d(set2, set1)

def instance_dataset_distance(instance, dataset, metric_function):
    """
    Calculates the distance between instance and dataset as the
    distance from the given instance to the closest instance from the
    dataset.
    """
    return min(imap(lambda i2: metric_function(instance, i2), dataset))

def hamming(i1, i2):
    return sum(imap(operator.ne, i1, i2))

def euclidean(i1, i2):
    def diff(x, y):
        try:
            return x - y
        except TypeError:
            return int(x != y)

    return sqrt(sum(imap(lambda x, y: diff(x,y)**2, i1, i2)))

cpdef dict data_distribution_nn(data):
    cdef int n_attrs, subset_size
    cdef list indices
    cdef dict distr, sdistr

    n_attrs = len(data.domain)
    indices = range(n_attrs)
    #if n_attrs > 3:
    #  n_attrs = 3
    distr = {}
    for subset_size in xrange(1, n_attrs+1):
        for subset in combinations(indices, subset_size):
            #subset += (n_attrs-1,)
            sdistr = {}
            for d in data:
                val = tuple([d[i].value for i in subset])
                if val not in sdistr:
                    sdistr[val] = 0
                sdistr[val] += 1
            distr[subset] = sdistr
    return distr

def kirkwood_approx(var_set, instance, distr):
    """
    Kirkwood approximation of joint probability.
    var_set -- joint variables set
    instance -- instantiation of all attributes values
    distr -- known joint probability distributions
    """
    return reduce(operator.div, (subsets_prob_product(i, var_set, instance, distr)
                                 for i in xrange(len(var_set)-1, 0, -1)))

def subsets_prob_product(n, var_set, instance, distr):
    return reduce(operator.mul, (prob(vs, instance, distr)
                                 for vs in combinations(var_set, n)))

cpdef double prob(var_set, instance, distr):
    if var_set in distr:
        val = tuple([instance[i].value for i in var_set])
        if val in distr[var_set]:
            return distr[var_set][val]
        elif len(var_set) == 1:
            return 0.0
    return kirkwood_approx(var_set, instance, distr)

cpdef dict normalize_distribution(distr, int n):
    return {subset: {val: (float(count) / n)
                          for (val, count) in sdistr.iteritems()}
                    for (subset, sdistr) in distr.iteritems()}

cpdef dict data_distribution(data):
    """
    Calculates a discrete distribution of values in the dataset. All the
    possible combinations of attributes are taken into account.
    """
    cdef int n
    cdef dict distr

    distr = data_distribution_nn(data)
    n = len(data) * len(distr)
    #n = len(data)
    for subset in distr:
        for val in distr[subset]:
            distr[subset][val] = float(distr[subset][val]) / n
    return distr
   
cpdef dict distribution_nn_add_instance(dict distr, instance):
    """
    Updates data distribution after adding a new instance.
    """
    for subset in distr:
        sdistr = distr[subset]
        val = tuple([instance[i].value for i in subset])
        if val not in sdistr:
            sdistr[val] = 0
        sdistr[val] += 1
    return distr

cpdef dict distribution_nn_remove_instance(dict distr, instance):
    """
    Updates data distribution after removing an instance.
    """
    for subset in distr:
        sdistr = distr[subset]
        val = tuple([instance[i].value for i in subset])
        sdistr[val] -= 1
    return distr

cpdef double hellinger_distance(dict cdistr1, dict cdistr2):
    """
    Sum of Hellinger distances for two sets of analogous distributions.
    """
    cdef double s
    s = 0
    for k in cdistr1:
        if k in cdistr2:
            s += hellinger_distance_p(cdistr1[k], cdistr2[k])
        else:
            s += hellinger_distance_p(cdistr1[k], {})
    for k in cdistr2:
        if not k in cdistr1:
            s += hellinger_distance_p({}, cdistr2[k])
    return sqrt(s/2)

cpdef double hellinger_distance_p(dict distr1, dict distr2):
    """
    Calculates Hellinger distance between two discrete probability
    distributions.
    """
    cdef double s, a, b, c
    s = 0
    for v in distr1:
        a = distr1[v]
        if v in distr2:
            b = distr2[v]
            c = sqrt(a) - sqrt(b)
            s += c * c
        else:
            s += a
    for v in distr2:
        if v not in distr1:
            b = distr2[v]
            s += b
    return s

cdef double cond_entropy(dict distr):
    """
    Calculates conditional entropy H(Y|X), where Y is the class variable and X
    the vector of attributes.
    """
    cdef double s, p_xy, p_x
    cdef tuple k1, k2, l 
    s = 0
    for k1 in distr:
        for k2 in distr[k1]:
            p_xy = distr[k1][k2]
            p_x = 0
            for l in distr[k1]:
                if l[:-1] == k2[:-1]:
                    p_x += distr[k1][l]
            s += p_xy * log2(p_x / p_xy)
    return s

cpdef double fano_min_error(dict distr, int class_n):
    return (cond_entropy(distr) - 1) / log2(class_n)

#cpdef str bayes_max_class(dict distr):
    

cpdef double cdistr_total_sum(dict cdistr):
    cdef double total_sum, v
    total_sum = 0
    for d in cdistr:
       for v in cdistr[d].itervalues():
          total_sum += v 
    return total_sum

cpdef double hellinger_distance_subset(dict cdistr1, dict cdistr2, double cdistr2_sum):
    cdef double s, a, b
    s = 0
    for k in cdistr1:
       for v in cdistr1[k]:
          a = cdistr1[k][v]
          b = cdistr2[k][v]
          cdistr2_sum += a - 2*sqrt(a*b)
    return sqrt(cdistr2_sum/2)

def kl_divergence(distr1, distr2):
    """
    Calculates Kullback-Leibner divergence between two discrete probability
    distributions. Divergence is well defined if every value from
    distr1 is included in distr2.
    
    distr1 can be treated as the "real" distribution and distr2 is
    is estimated distribution com
    """
    s = 0
    for v in distr1:
        if v in distr2:
            s += log(distr1[v] / distr2[v], 2) * distr1[v]
    return s

cpdef indices_gen(int p, rand, data):
        cdef int n
        n = len(data)
        if p == n:
            return [0] * p
        if p == 1:
            ind = [1] * n
            ind[rand(n)] = 0
            return ind
        indices2 = Orange.data.sample.SubsetIndices2(p0=p)
        indices2.random_generator = rand
        return indices2(data)

cpdef tuple random_subset_dist(ddata, ddata_distr, int n, rand=Orange.misc.Random(0)):
    """
    Draws a random subset of size n from the data and returns it along with its Hellinger
    distance from the whole dataset. Subset is represented with binary mask; 1 at i-th place
    means that i-th example belongs to the subset.
    """
    smask = indices_gen(n, rand, ddata)
    sdata = ddata.select(smask, 0)
    sdata_distr = data_distribution(sdata)
    return smask, hellinger_distance(sdata_distr, ddata_distr)

#cpdef tuple random_subset_dist_opt(ddata, ddata_distr,
#                                   double ddata_sum, int n,
#                                   rand=Orange.misc.Random(0)):
#    smask = indices_gen(n, rand, ddata)
#    sdata = ddata.select(smask, 0)
#    sdata_distr = data_distribution(sdata)
#    return smask, hellinger_distance_subset(sdata_distr, ddata_distr,
#                                            ddata_sum)

cdef int MC_ITERATIONS
MC_ITERATIONS = 50
#MC_ITERATIONS = 1

def build_minmax_subsets_list_mc(data, subset_sizes = None, rand=Orange.misc.Random(0)):
    """
    Builds a list of subsets of different sizes minimized in terms of Hellinger
    distance from the whole dataset. Uses Monte Carlo approach.
    """
    cdef int i, j
    cdef double d, min_d
    cdef list subsets_list

    ddata = Orange.data.discretization.DiscretizeTable(data,
                   method=Orange.feature.discretization.EqualWidth(n=len(data)/20))
    #ddata = Orange.data.discretization.DiscretizeTable(data,
    #               method=Orange.feature.discretization.EqualFreq(n=len(data)))
    ddata_distr = data_distribution(ddata)

    min_subsets_list = []
    max_subsets_list = []
    if not subset_sizes:
        subset_sizes = range(len(data)+1)
    for i in subset_sizes:
        min_subset, min_d = random_subset_dist(ddata, ddata_distr,
                                               i, rand)
        max_subset, max_d = min_subset, min_d
        for j in range(MC_ITERATIONS-1):
            subset, d = random_subset_dist(ddata, ddata_distr,
                                           i, rand)
            if d < min_d:
                min_subset = subset
                min_d = d
            if d > max_d:
                max_subset = subset
                max_d = d
        min_subsets_list.append((min_subset, min_d))
        max_subsets_list.append((max_subset, max_d))
    return (min_subsets_list, max_subsets_list)

def build_subsets_dec_dist(data, minimalize=True):
    """
    Builds a list of subsets of the whole dataset iteratively using greedy approach
    based on Hellinger distance minimalization/maximalization. Each subset is represented
    as a list of 0's and 1's, 1 at i-th place means that i-th example belongs to the subset.
    
    TODO: Refactor
    """
    ddata = Orange.data.discretization.DiscretizeTable(data,
                   method=Orange.feature.discretization.EqualFreq(n=len(data)))

    data_distr = data_distribution(ddata)
    unassigned_data_ind = range(len(data))
    sets = [[0] * len(data)]
    sets_dists = []
    cdistr = data_distribution_nn(ddata.select(sets[-1], 1)) 
    while len(unassigned_data_ind):
        cset = ddata.select(sets[-1], 1)
        dists = []
        for i in unassigned_data_ind:
            cset.append(ddata[i])
            distribution_nn_add_instance(cdistr, ddata[i])
            dists.append(hellinger_distance(normalize_distribution(cdistr,
                len(cset)*len(cdistr)), data_distr))
            del cset[-1]
            distribution_nn_remove_instance(cdistr, ddata[i])
        if minimalize:
            idx = min(xrange(len(dists)), key=dists.__getitem__)
        else:
            idx = max(xrange(len(dists)), key=dists.__getitem__)
        sets_dists.append(dists[idx])
        nset = sets[-1][:]
        nset[unassigned_data_ind[idx]] = 1
        sets.append(nset)
        distribution_nn_add_instance(cdistr, ddata[unassigned_data_ind[idx]])
        del unassigned_data_ind[idx]

    del sets[0]
    return sets, sets_dists
